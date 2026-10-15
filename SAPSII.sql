DROP TABLE IF EXISTS public.eicu_af_bcr_sapsii;
CREATE TABLE public.eicu_af_bcr_sapsii AS
WITH base AS (SELECT stay_id, age FROM public.eicu_af_bcr_cohort),
vv AS (
 SELECT v.patientunitstayid stay_id,
 MAX(CASE WHEN v.heartrate <40 THEN 11 WHEN v.heartrate <70 THEN 2 WHEN v.heartrate <120 THEN 0 WHEN v.heartrate <160 THEN 4 WHEN v.heartrate IS NOT NULL THEN 7 END) hr_pts,
 MAX(CASE WHEN COALESCE(v.ibp_systolic,v.nibp_systolic)<70 THEN 13 WHEN COALESCE(v.ibp_systolic,v.nibp_systolic)<100 THEN 5 WHEN COALESCE(v.ibp_systolic,v.nibp_systolic)<200 THEN 0 WHEN COALESCE(v.ibp_systolic,v.nibp_systolic) IS NOT NULL THEN 2 END) sbp_pts,
 MAX(CASE WHEN v.temperature >=39 THEN 3 WHEN v.temperature BETWEEN 25 AND 42 THEN 0 END) temp_pts
 FROM eicu_derived.pivoted_vital v JOIN base b ON b.stay_id=v.patientunitstayid
 WHERE v.chartoffset BETWEEN 0 AND 1439 GROUP BY 1
),
ll AS (
 SELECT l.patientunitstayid stay_id,
 MAX(CASE WHEN l.bun>=84 THEN 10 WHEN l.bun>=28 THEN 6 WHEN l.bun>=0 THEN 0 END) bun_pts,
 MAX(CASE WHEN l.wbc<1 THEN 12 WHEN l.wbc<20 THEN 0 WHEN l.wbc IS NOT NULL THEN 3 END) wbc_pts,
 MAX(CASE WHEN l.potassium<3 THEN 3 WHEN l.potassium<5 THEN 0 WHEN l.potassium IS NOT NULL THEN 3 END) potassium_pts,
 MAX(CASE WHEN l.sodium<125 THEN 5 WHEN l.sodium<145 THEN 0 WHEN l.sodium IS NOT NULL THEN 1 END) sodium_pts,
 MAX(CASE WHEN COALESCE(l.bicarbonate,l.totalco2)<15 THEN 6 WHEN COALESCE(l.bicarbonate,l.totalco2)<20 THEN 3 WHEN COALESCE(l.bicarbonate,l.totalco2) IS NOT NULL THEN 0 END) hco3_pts,
 MAX(CASE WHEN l.bilirubin>=6 THEN 9 WHEN l.bilirubin>=4 THEN 4 WHEN l.bilirubin>=0 THEN 0 END) bilirubin_pts
 FROM eicu_derived.pivoted_lab l JOIN base b ON b.stay_id=l.patientunitstayid
 WHERE l.chartoffset BETWEEN 0 AND 1439 GROUP BY 1
),
gg AS (
 SELECT g.patientunitstayid stay_id,
 MAX(CASE WHEN g.gcs <6 THEN 26 WHEN g.gcs<=8 THEN 13 WHEN g.gcs<=10 THEN 7 WHEN g.gcs<=13 THEN 5 WHEN g.gcs<=15 THEN 0 END) gcs_pts
 FROM eicu_derived.pivoted_gcs g JOIN base b ON b.stay_id=g.patientunitstayid
 WHERE g.chartoffset BETWEEN 0 AND 1439 GROUP BY 1
),
rr AS (
 SELECT u.patientunitstayid stay_id, SUM(u.urineoutput) urine_ml,
 COUNT(u.urineoutput) n_urine
 FROM eicu_derived.pivoted_uo u JOIN base b ON b.stay_id=u.patientunitstayid
 WHERE u.chartoffset BETWEEN 0 AND 1439 AND u.urineoutput BETWEEN 0 AND 10000
 GROUP BY 1
),
ap AS (
 SELECT patientunitstayid stay_id,
 MAX(CASE WHEN ventday1=1 THEN 1 ELSE 0 END) ventday1,
 MAX(CASE WHEN electivesurgery=1 THEN 1 WHEN electivesurgery=0 THEN 0 END) elective_surgery,
 MAX(CASE WHEN meds=1 THEN 1 WHEN meds=0 THEN 0 END) is_medical,
 MAX(CASE WHEN aids=1 THEN 1 ELSE 0 END) aids,
 MAX(CASE WHEN lymphoma=1 OR leukemia=1 THEN 1 ELSE 0 END) heme_malignancy,
 MAX(CASE WHEN metastaticcancer=1 THEN 1 ELSE 0 END) metastatic
 FROM public.apachepredvar a JOIN base b ON b.stay_id=a.patientunitstayid GROUP BY 1
),
vent AS (
 SELECT b.stay_id,
 CASE WHEN COALESCE(a.ventday1,0)=1
 OR EXISTS (SELECT 1 FROM public.respiratorycare r WHERE r.patientunitstayid=b.stay_id AND r.ventstartoffset<1440 AND (r.ventendoffset IS NULL OR r.ventendoffset>=0))
 OR EXISTS (SELECT 1 FROM eicu_derived.pivoted_o2 o WHERE o.patientunitstayid=b.stay_id AND o.chartoffset BETWEEN 0 AND 1439 AND (o.o2_device ILIKE '%cpap%' OR o.o2_device ILIKE '%bipap%'))
 THEN 1 ELSE 0 END support
 FROM base b LEFT JOIN ap a USING(stay_id)
),
bg AS (
 SELECT x.patientunitstayid stay_id,
 MIN(x.pao2 / NULLIF(CASE WHEN x.fio2>1 THEN x.fio2/100.0 ELSE x.fio2 END,0)) pf_min,
 COUNT(*) FILTER (WHERE x.pao2>0 AND x.fio2>0) n_pf
 FROM eicu_derived.pivoted_bg x JOIN base b ON b.stay_id=x.patientunitstayid
 WHERE x.chartoffset BETWEEN 0 AND 1439 AND x.pao2>0 AND x.fio2 BETWEEN 0.21 AND 100
 GROUP BY 1
),
components AS (
 SELECT b.stay_id,b.age,
 CASE WHEN b.age<40 THEN 0 WHEN b.age<60 THEN 7 WHEN b.age<70 THEN 12 WHEN b.age<75 THEN 15 WHEN b.age<80 THEN 16 ELSE 18 END age_pts,
 v.hr_pts,v.sbp_pts,v.temp_pts,l.bun_pts,l.wbc_pts,l.potassium_pts,l.sodium_pts,l.hco3_pts,l.bilirubin_pts,g.gcs_pts,
 CASE WHEN r.n_urine>0 THEN CASE WHEN r.urine_ml<500 THEN 11 WHEN r.urine_ml<1000 THEN 4 ELSE 0 END END urine_pts,
 r.urine_ml,r.n_urine,
 z.support AS respiratory_support,
 x.pf_min,
 CASE WHEN z.support=1 AND x.pf_min<100 THEN 11 WHEN z.support=1 AND x.pf_min<200 THEN 9 WHEN z.support=1 AND x.pf_min IS NOT NULL THEN 6 WHEN z.support=0 THEN 0 END oxygen_pts,
 -- SAPS II admission type: medical 6, scheduled surgical 0, unscheduled surgical 8
 CASE WHEN a.is_medical=1 THEN 6 WHEN a.elective_surgery=1 THEN 0 WHEN a.is_medical=0 AND a.elective_surgery=0 THEN 8 END admission_pts,
 GREATEST(CASE WHEN a.aids=1 THEN 17 ELSE 0 END,CASE WHEN a.heme_malignancy=1 THEN 10 ELSE 0 END,CASE WHEN a.metastatic=1 THEN 9 ELSE 0 END) comorbidity_pts,
 a.is_medical,a.elective_surgery
 FROM base b LEFT JOIN vv v USING(stay_id) LEFT JOIN ll l USING(stay_id)
 LEFT JOIN gg g USING(stay_id) LEFT JOIN rr r USING(stay_id) LEFT JOIN ap a USING(stay_id)
 LEFT JOIN vent z USING(stay_id) LEFT JOIN bg x USING(stay_id)
)
SELECT *,
 (age_pts+COALESCE(hr_pts,0)+COALESCE(sbp_pts,0)+COALESCE(temp_pts,0)
 +COALESCE(bun_pts,0)+COALESCE(wbc_pts,0)+COALESCE(potassium_pts,0)+COALESCE(sodium_pts,0)
 +COALESCE(hco3_pts,0)+COALESCE(bilirubin_pts,0)+COALESCE(gcs_pts,0)+COALESCE(urine_pts,0)
 +COALESCE(oxygen_pts,0)+COALESCE(admission_pts,0)+COALESCE(comorbidity_pts,0)) AS sapsii_preliminary,
 ( (hr_pts IS NULL)::int+(sbp_pts IS NULL)::int+(temp_pts IS NULL)::int+(bun_pts IS NULL)::int
 +(wbc_pts IS NULL)::int+(potassium_pts IS NULL)::int+(sodium_pts IS NULL)::int
 +(hco3_pts IS NULL)::int+(bilirubin_pts IS NULL)::int+(gcs_pts IS NULL)::int
 +(urine_pts IS NULL)::int+(oxygen_pts IS NULL)::int+(admission_pts IS NULL)::int ) AS missing_component_count
FROM components;
CREATE UNIQUE INDEX ON public.eicu_af_bcr_sapsii(stay_id);
