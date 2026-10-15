DROP TABLE IF EXISTS public.eicu_af_bcr_crrt;
CREATE TABLE public.eicu_af_bcr_crrt AS
WITH t AS (
 SELECT c.stay_id,
 MAX(CASE WHEN lower(t.treatmentstring) ~ '(continuous renal replacement|\bcrrt\b|\bcvvh\b|\bcvvhd\b|\bcvvhdf\b)'
 THEN 1 ELSE 0 END) AS crrt_recorded_24h,
 MAX(CASE WHEN lower(t.treatmentstring) ~ '(dialysis|renal replacement|hemofiltration|\bcrrt\b)'
 THEN 1 ELSE 0 END) AS rrt_recorded_24h
 FROM public.eicu_af_bcr_cohort c LEFT JOIN public.treatment t
 ON t.patientunitstayid=c.stay_id AND t.treatmentoffset>=0 AND t.treatmentoffset<1440
 GROUP BY c.stay_id
)
SELECT c.stay_id,c.hospital_stay_id,t.crrt_recorded_24h,t.rrt_recorded_24h
FROM public.eicu_af_bcr_cohort c LEFT JOIN t USING(stay_id);

