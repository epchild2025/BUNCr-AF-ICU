-- 07. Charlson
DROP TABLE IF EXISTS public.af_bcr_charlson;
CREATE TABLE public.af_bcr_charlson AS
SELECT c.subject_id,c.hadm_id,c.stay_id,
 ch.charlson_comorbidity_index AS charlson_score
FROM public.af_bcr_cohort c
LEFT JOIN mimiciv_derived.charlson ch ON ch.hadm_id=c.hadm_id;
