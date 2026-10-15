DROP TABLE IF EXISTS public.eicu_af_bcr_scores;
CREATE TABLE public.eicu_af_bcr_scores AS
SELECT c.stay_id, c.hospital_stay_id,
       NULL::numeric AS apsiii,
       o.oasis::numeric AS oasis,
       NULL::numeric AS sapsii,
       NULL::numeric AS sofa_score,
       CASE WHEN o.oasis IS NULL THEN 0 ELSE 1 END AS oasis_record_available
FROM public.eicu_af_bcr_cohort c
LEFT JOIN eicu_derived.pivoted_oasis o
 ON o.patientunitstayid=c.stay_id;
-- These NULL columns are NOT external-validation-ready. See README.
