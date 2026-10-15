DROP TABLE IF EXISTS public.eicu_af_bcr_candidate;
CREATE TABLE public.eicu_af_bcr_candidate AS
WITH af AS (
 SELECT DISTINCT patientunitstayid
 FROM public.diagnosis
 WHERE (replace(upper(coalesce(icd9code,'')),'.','') ~ '(^|[^0-9])42731([^0-9]|$)'
        OR lower(coalesce(diagnosisstring,'')) LIKE '%atrial fibrillation%')
), eligible AS (
 SELECT p.*,
  CASE WHEN trim(p.age) IN ('> 89','>89') THEN 90
       WHEN trim(p.age) ~ '^[0-9]+$' THEN trim(p.age)::int ELSE NULL END AS age_num,
  row_number() OVER(PARTITION BY p.uniquepid ORDER BY p.hospitaldischargeyear,p.patienthealthsystemstayid,p.unitvisitnumber,p.patientunitstayid) AS patient_rn
 FROM public.patient p JOIN af USING(patientunitstayid)
 WHERE p.unitvisitnumber=1
   AND p.unitdischargeoffset>1440
   AND p.hospitaldischargeoffset>1440
   AND upper(trim(coalesce(p.hospitaldischargestatus,''))) IN ('ALIVE','EXPIRED')
)
SELECT patientunitstayid AS stay_id, patienthealthsystemstayid AS hospital_stay_id,
 uniquepid, hospitalid, gender, age_num AS age, ethnicity AS race,
 admissionheight AS height_cm, admissionweight AS weight_kg,
 hospitaladmitoffset,hospitaldischargeoffset,unitdischargeoffset,
 hospitaldischargestatus,unitdischargestatus,
 CASE WHEN upper(trim(hospitaldischargestatus))='EXPIRED' THEN 1 ELSE 0 END AS hospital_mortality,
 1440::int AS prediction_offset_minutes,
 1::int AS af_diagnosis_recorded
FROM eligible WHERE patient_rn=1 AND age_num>=65;
CREATE UNIQUE INDEX eicu_af_candidate_stay_idx ON public.eicu_af_bcr_candidate(stay_id);
