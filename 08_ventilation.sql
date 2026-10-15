-- 09. 有创机械通气
DROP TABLE IF EXISTS public.af_bcr_ventilation;
CREATE TABLE public.af_bcr_ventilation AS
SELECT c.subject_id,c.hadm_id,c.stay_id,
 CASE WHEN COUNT(v.stay_id)>0 THEN 1 ELSE 0 END AS mech_vent
FROM public.af_bcr_cohort c
LEFT JOIN mimiciv_derived.ventilation v ON v.stay_id=c.stay_id
 AND v.ventilation_status='InvasiveVent'
 AND v.starttime<c.prediction_time AND v.endtime>c.icu_intime
GROUP BY c.subject_id,c.hadm_id,c.stay_id;
