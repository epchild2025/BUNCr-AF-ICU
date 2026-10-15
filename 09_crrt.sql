-- 09
-- 如果本地 crrt 表不含 crrt_mode，请核对官方版本再改。
DROP TABLE IF EXISTS public.af_bcr_crrt;
CREATE TABLE public.af_bcr_crrt AS
SELECT c.subject_id,c.hadm_id,c.stay_id,
 CASE WHEN COUNT(r.charttime)>0 THEN 1 ELSE 0 END AS crrt_24h
FROM public.af_bcr_cohort c LEFT JOIN mimiciv_derived.crrt r
 ON r.stay_id=c.stay_id AND r.charttime>=c.icu_intime AND r.charttime<c.prediction_time
 AND r.crrt_mode IS NOT NULL
GROUP BY c.subject_id,c.hadm_id,c.stay_id;
