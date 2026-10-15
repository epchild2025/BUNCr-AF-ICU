DROP TABLE IF EXISTS public.eicu_af_bcr_sofa_final;
CREATE TABLE public.eicu_af_bcr_sofa_final AS
WITH base AS (
    SELECT DISTINCT stay_id FROM public.eicu_af_bcr_cohort
),
-- Prefer worst observed component within 24h, not last/first reading.
lab AS (
    SELECT l.patientunitstayid AS stay_id,
      MIN(l.platelets) FILTER (WHERE l.platelets BETWEEN 1 AND 1500) AS min_platelets,
      MAX(l.bilirubin) FILTER (WHERE l.bilirubin BETWEEN 0 AND 100) AS max_bilirubin,
      MAX(l.creatinine) FILTER (WHERE l.creatinine BETWEEN 0.01 AND 40) AS max_creatinine
    FROM eicu_derived.pivoted_lab l JOIN base b ON b.stay_id=l.patientunitstayid
    WHERE l.chartoffset >= 0 AND l.chartoffset < 1440 GROUP BY 1
),
gcs AS (
    SELECT g.patientunitstayid AS stay_id,
           MIN(g.gcs) FILTER (WHERE g.gcs BETWEEN 3 AND 15) AS min_gcs
    FROM eicu_derived.pivoted_gcs g JOIN base b ON b.stay_id=g.patientunitstayid
    WHERE g.chartoffset >= 0 AND g.chartoffset < 1440 GROUP BY 1
),
map_data AS (
    SELECT v.patientunitstayid AS stay_id,
           MIN(v.ibp_mean) FILTER (WHERE v.ibp_mean BETWEEN 20 AND 250) AS min_ibp,
           MIN(v.nibp_mean) FILTER (WHERE v.nibp_mean BETWEEN 20 AND 250) AS min_nibp
    FROM eicu_derived.pivoted_vital v JOIN base b ON b.stay_id=v.patientunitstayid
    WHERE v.chartoffset >= 0 AND v.chartoffset < 1440 GROUP BY 1
),
-- The pivoted_uo.urineoutput should be verified as incremental, not rolling total.
-- No inference that fewer than 24h of urine charts is a full 24-hour collection.
urine AS (
    SELECT u.patientunitstayid AS stay_id,
           SUM(u.urineoutput) FILTER (WHERE u.urineoutput BETWEEN 0 AND 3000) AS urine_ml,
           COUNT(u.urineoutput) FILTER (WHERE u.urineoutput BETWEEN 0 AND 3000) AS urine_records,
           MAX(u.chartoffset)-MIN(u.chartoffset) AS urine_span_minutes
    FROM eicu_derived.pivoted_uo u JOIN base b ON b.stay_id=u.patientunitstayid
    WHERE u.chartoffset >= 0 AND u.chartoffset < 1440 GROUP BY 1
),
-- SAME-record PaO2 and FiO2 only; no global max FiO2/min PaO2 mix.
-- FiO2 is either a fraction (0.21..1) or percent (21..100).
pf AS (
    SELECT z.patientunitstayid AS stay_id,
           MIN(z.pao2 / NULLIF(CASE WHEN z.fio2>1 THEN z.fio2/100.0 ELSE z.fio2 END,0))
           FILTER (WHERE z.pao2 BETWEEN 20 AND 800
                    AND ((z.fio2 BETWEEN 0.21 AND 1) OR (z.fio2 BETWEEN 21 AND 100))) AS pf_min,
           COUNT(*) FILTER (WHERE z.pao2 BETWEEN 20 AND 800
                    AND ((z.fio2 BETWEEN 0.21 AND 1) OR (z.fio2 BETWEEN 21 AND 100))) AS paired_bg_rows
    FROM eicu_derived.pivoted_bg z JOIN base b ON b.stay_id=z.patientunitstayid
    WHERE z.chartoffset >= 0 AND z.chartoffset < 1440 GROUP BY 1
),
-- Respiratory support evidence recorded inside window.
-- APACHE ventday1 is intentionally NOT used because the underlying calculation
-- and timing may not match the 0-24h landmark.
vent_rc AS (
   SELECT DISTINCT r.patientunitstayid AS stay_id
   FROM public.respiratorycare r JOIN base b ON b.stay_id=r.patientunitstayid
   WHERE (r.ventstartoffset < 1440 AND (r.ventendoffset IS NULL OR r.ventendoffset >= 0))
      OR (r.respcarestatusoffset >= 0 AND r.respcarestatusoffset < 1440
          AND r.airwaytype IN ('Oral ETT','Nasal ETT','Tracheostomy'))
),
vent_chart AS (
   SELECT DISTINCT r.patientunitstayid AS stay_id
   FROM public.respiratorycharting r JOIN base b ON b.stay_id=r.patientunitstayid
   WHERE r.respchartoffset >= 0 AND r.respchartoffset < 1440
     AND (
       LOWER(COALESCE(r.respchartvalue,'')) ~ '(ventilator|bipap|cpap|servo|drager)'
       OR LOWER(COALESCE(r.respchartvaluelabel,'')) ~ '(ventilator mode|vent mode|ventilator type)'
     )
),
vent AS (
   SELECT b.stay_id,
      CASE WHEN rc.stay_id IS NOT NULL OR vc.stay_id IS NOT NULL THEN 1 ELSE 0 END AS respiratory_support
   FROM base b LEFT JOIN vent_rc rc USING(stay_id) LEFT JOIN vent_chart vc USING(stay_id)
),
-- The source file used 80kg fixed weight and assumed a fixed IV concentration
-- for mL/hr: these conversions are NOT valid as general patient-level conversions.
-- Interpret explicit mcg/kg/min, mcg/min, mcg/hr, mg/kg/min, mg/min with
-- patientweight from infusiondrug where required. mL/hr for pressors with
-- unknown concentration remains unresolved; dobutamine with positive mL/hr
-- supports SOFA cardiovascular >=2 without assuming its dose.
-- An established 4-point pressor score supersedes unresolved parallel infusions.
pressor_input AS (
    SELECT i.patientunitstayid AS stay_id, i.drugname, i.drugrate,
       i.patientweight AS patientweight_raw,
       CASE WHEN TRIM(i.patientweight::text) ~ '^[0-9]+(\.[0-9]+)?$'
                 AND LENGTH(TRIM(i.patientweight::text)) <= 12
            THEN CASE WHEN TRIM(i.patientweight::text)::numeric BETWEEN 20 AND 300
                      THEN TRIM(i.patientweight::text)::numeric END
            ELSE NULL END AS weight_kg,
       CASE WHEN i.drugrate ~ '^\s*[0-9]+(\.[0-9]+)?\s*$'
            THEN TRIM(i.drugrate)::numeric END AS rate,
       CASE WHEN LOWER(COALESCE(i.drugname,'')) ~ '(norepineph|levophed)' THEN 'norepi'
            WHEN LOWER(COALESCE(i.drugname,'')) ~ 'epineph' THEN 'epi'
            WHEN LOWER(COALESCE(i.drugname,'')) ~ 'dopamin' THEN 'dopamine'
            WHEN LOWER(COALESCE(i.drugname,'')) ~ 'dobutamin' THEN 'dobutamine' END AS drug,
       LOWER(COALESCE(i.drugname,'')) AS drugname_lower
    FROM public.infusiondrug i JOIN base b ON b.stay_id=i.patientunitstayid
    WHERE i.infusionoffset >= 0 AND i.infusionoffset < 1440
      AND LOWER(COALESCE(i.drugname,'')) ~ '(norepineph|levophed|epineph|dopamin|dobutamin)'
),
pressor_norm AS (
    SELECT p.*,
      CASE
        WHEN p.rate IS NULL THEN NULL
        WHEN p.drugname_lower LIKE '%mcg/kg/min%' THEN p.rate
        WHEN p.drugname_lower LIKE '%mcg/min%'
           AND p.weight_kg IS NOT NULL THEN p.rate/p.weight_kg
        WHEN p.drugname_lower LIKE '%mcg/hr%'
           AND p.weight_kg IS NOT NULL THEN p.rate/60.0/p.weight_kg
        WHEN p.drugname_lower LIKE '%mg/kg/min%' THEN p.rate*1000.0
        WHEN p.drugname_lower LIKE '%mg/min%'
           AND p.weight_kg IS NOT NULL THEN p.rate*1000.0/p.weight_kg
        ELSE NULL
      END AS rate_mcg_kg_min,
      CASE WHEN p.rate=0 THEN 0
        WHEN p.drugname_lower LIKE '%mcg/kg/min%' THEN 0
        WHEN p.drugname_lower LIKE '%mcg/min%' AND p.weight_kg IS NOT NULL THEN 0
        WHEN p.drugname_lower LIKE '%mcg/hr%' AND p.weight_kg IS NOT NULL THEN 0
        WHEN p.drugname_lower LIKE '%mg/kg/min%' THEN 0
        WHEN p.drugname_lower LIKE '%mg/min%' AND p.weight_kg IS NOT NULL THEN 0
        WHEN p.drug='dobutamine' AND p.rate>0 AND p.drugname_lower LIKE '%ml/hr%' THEN 0
        ELSE 1 END AS unit_unresolved
    FROM pressor_input p
),
pressor AS (
   SELECT stay_id,
      COUNT(*) AS pressor_rows,
      COUNT(*) FILTER (WHERE rate_mcg_kg_min>0 OR (drug='dobutamine' AND rate>0 AND drugname_lower LIKE '%ml/hr%')) AS rate_valid_rows,
      COUNT(*) FILTER (WHERE unit_unresolved=1) AS unresolved_pressor_rows,
      MAX(CASE
          WHEN drug='dopamine' AND rate_mcg_kg_min>15 THEN 4
          WHEN drug IN ('epi','norepi') AND rate_mcg_kg_min>0.1 THEN 4
          WHEN drug='dopamine' AND rate_mcg_kg_min>5 THEN 3
          WHEN drug IN ('epi','norepi') AND rate_mcg_kg_min>0 THEN 3
          WHEN drug='dopamine' AND rate_mcg_kg_min>0 THEN 2
          WHEN drug='dobutamine' AND (rate_mcg_kg_min>0 OR (rate>0 AND drugname_lower LIKE '%ml/hr%')) THEN 2
          END) AS drug_pts
   FROM pressor_norm GROUP BY 1
),
pressor_flags AS (
   SELECT t.patientunitstayid AS stay_id,
      MAX(CASE WHEN COALESCE(t.dopamine,0)>0 OR COALESCE(t.dobutamine,0)>0
          OR COALESCE(t.norepinephrine,0)>0 OR COALESCE(t.epinephrine,0)>0
          THEN 1 ELSE 0 END) AS recorded
   FROM eicu_derived.pivoted_infusion t JOIN base b ON b.stay_id=t.patientunitstayid
   WHERE t.chartoffset >= 0 AND t.chartoffset < 1440 GROUP BY 1
),
raw_components AS (
   SELECT b.stay_id, l.min_platelets,l.max_bilirubin,l.max_creatinine,
      g.min_gcs, LEAST(m.min_ibp,m.min_nibp) AS min_map,
      u.urine_ml,u.urine_records,u.urine_span_minutes,
      pf.pf_min,pf.paired_bg_rows,v.respiratory_support,
      p.pressor_rows,p.rate_valid_rows,p.unresolved_pressor_rows,p.drug_pts,
      COALESCE(f.recorded,0) AS pressor_flag,
      CASE WHEN l.min_platelets<20 THEN 4 WHEN l.min_platelets<50 THEN 3
           WHEN l.min_platelets<100 THEN 2 WHEN l.min_platelets<150 THEN 1
           WHEN l.min_platelets IS NOT NULL THEN 0 END AS coag_pts,
      CASE WHEN l.max_bilirubin>=12 THEN 4 WHEN l.max_bilirubin>=6 THEN 3
           WHEN l.max_bilirubin>=2 THEN 2 WHEN l.max_bilirubin>=1.2 THEN 1
           WHEN l.max_bilirubin IS NOT NULL THEN 0 END AS liver_pts,
      CASE WHEN g.min_gcs<6 THEN 4 WHEN g.min_gcs<10 THEN 3
           WHEN g.min_gcs<13 THEN 2 WHEN g.min_gcs<15 THEN 1
           WHEN g.min_gcs=15 THEN 0 END AS neuro_pts,
      CASE WHEN l.max_creatinine>=5 THEN 4 WHEN l.max_creatinine>=3.5 THEN 3
           WHEN l.max_creatinine>=2 THEN 2 WHEN l.max_creatinine>=1.2 THEN 1
           WHEN l.max_creatinine IS NOT NULL THEN 0 END AS creat_pts,
      CASE WHEN pf.pf_min<100 AND v.respiratory_support=1 THEN 4
           WHEN pf.pf_min<200 AND v.respiratory_support=1 THEN 3
           WHEN pf.pf_min<300 THEN 2 WHEN pf.pf_min<400 THEN 1
           WHEN pf.pf_min IS NOT NULL THEN 0 END AS resp_pts,
      -- Urine points remain for analysis but MUST NOT be used as an automatic
      -- 24-hour measure without checking chart frequency/coverage.
      CASE WHEN u.urine_records>0 AND u.urine_ml<200 THEN 4
           WHEN u.urine_records>0 AND u.urine_ml<500 THEN 3
           WHEN u.urine_records>0 THEN 0 END AS urine_pts_raw,
      CASE WHEN p.drug_pts=4 THEN 4
           WHEN COALESCE(p.unresolved_pressor_rows,0)>0
             OR (COALESCE(f.recorded,0)=1 AND COALESCE(p.rate_valid_rows,0)=0)
           THEN NULL
           WHEN p.drug_pts IS NOT NULL THEN GREATEST(p.drug_pts, CASE WHEN LEAST(m.min_ibp,m.min_nibp)<70 THEN 1 ELSE 0 END)
           WHEN LEAST(m.min_ibp,m.min_nibp)<70 THEN 1
           WHEN LEAST(m.min_ibp,m.min_nibp) IS NOT NULL THEN 0
           ELSE NULL END AS cardio_pts
   FROM base b
     LEFT JOIN lab l USING(stay_id) LEFT JOIN gcs g USING(stay_id)
     LEFT JOIN map_data m USING(stay_id) LEFT JOIN urine u USING(stay_id)
     LEFT JOIN pf USING(stay_id) LEFT JOIN vent v USING(stay_id)
     LEFT JOIN pressor p USING(stay_id) LEFT JOIN pressor_flags f USING(stay_id)
),
scored AS (
    SELECT r.*,
      -- Conservative renal score: creatinine is valid. Urine contribution is
      -- excluded from the official candidate until verified as 24h total.
      r.creat_pts AS renal_pts,
      (r.resp_pts IS NULL)::int + (r.coag_pts IS NULL)::int
       + (r.liver_pts IS NULL)::int + (r.cardio_pts IS NULL)::int
       + (r.neuro_pts IS NULL)::int + (r.creat_pts IS NULL)::int AS missing_component_count,
      CASE WHEN r.drug_pts=4 THEN 0
          WHEN COALESCE(r.unresolved_pressor_rows,0)>0
          OR (r.pressor_flag=1 AND COALESCE(r.rate_valid_rows,0)=0)
          THEN 1 ELSE 0 END AS pressor_review_flag
    FROM raw_components r
)
SELECT s.*,
  CASE WHEN missing_component_count=0
       THEN resp_pts+coag_pts+liver_pts+cardio_pts+neuro_pts+renal_pts END AS sofa_complete_case,
  CASE WHEN pressor_review_flag=0 THEN
       COALESCE(resp_pts,0)+COALESCE(coag_pts,0)+COALESCE(liver_pts,0)
        +COALESCE(cardio_pts,0)+COALESCE(neuro_pts,0)+COALESCE(renal_pts,0)
       END AS sofa_zero_missing_candidate,
  -- Original output name, deliberately NULL for unsafe/excluded records.
  CASE WHEN pressor_review_flag=0 THEN
       COALESCE(resp_pts,0)+COALESCE(coag_pts,0)+COALESCE(liver_pts,0)
        +COALESCE(cardio_pts,0)+COALESCE(neuro_pts,0)+COALESCE(renal_pts,0)
       END AS sofa_score
FROM scored s;
CREATE UNIQUE INDEX eicu_af_bcr_sofa_final_stay_id_idx
  ON public.eicu_af_bcr_sofa_final (stay_id);

-- QUALITY CHECKS
SELECT COUNT(*) AS n_rows,COUNT(DISTINCT stay_id) AS unique_stays,
 COUNT(sofa_complete_case) AS complete_case_available,
 COUNT(sofa_zero_missing_candidate) AS candidate_available,
 COUNT(*) FILTER (WHERE pressor_review_flag=1) AS pressor_review,
 ROUND(AVG(missing_component_count)::numeric,2) AS mean_missing_systems,
 MIN(sofa_score) AS min_sofa,MAX(sofa_score) AS max_sofa
FROM public.eicu_af_bcr_sofa_final;
SELECT
  COUNT(*) FILTER (WHERE resp_pts IS NULL) AS resp_missing,
  COUNT(*) FILTER (WHERE liver_pts IS NULL) AS liver_missing,
  COUNT(*) FILTER (WHERE coag_pts IS NULL) AS coag_missing,
  COUNT(*) FILTER (WHERE cardio_pts IS NULL) AS cv_missing,
  COUNT(*) FILTER (WHERE neuro_pts IS NULL) AS neuro_missing,
  COUNT(*) FILTER (WHERE renal_pts IS NULL) AS renal_missing
FROM public.eicu_af_bcr_sofa_final;

-- Additional checks for unresolved agents and possible dose outliers:
SELECT pressor_review_flag, COUNT(*) AS stays, COUNT(sofa_score) AS available,
       ROUND(AVG(sofa_zero_missing_candidate)::numeric,2) AS mean_candidate
FROM public.eicu_af_bcr_sofa_final GROUP BY 1 ORDER BY 1;
SELECT COUNT(*) FILTER(WHERE drug_pts=4) AS definite_cv_four,
       COUNT(*) FILTER(WHERE pressor_review_flag=1) AS pressor_unresolved,
       COUNT(*) FILTER(WHERE pf_min IS NULL) AS pf_missing,
       COUNT(*) FILTER(WHERE urine_span_minutes < 1200) AS urine_span_under20h
FROM public.eicu_af_bcr_sofa_final;
