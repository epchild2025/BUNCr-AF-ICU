-- 04. 生命体征：严格 ICU 0-24h 均值
DROP TABLE IF EXISTS public.af_bcr_vitals;
CREATE TABLE public.af_bcr_vitals AS
SELECT c.subject_id,c.hadm_id,c.stay_id,
 AVG(v.heart_rate) AS hr,AVG(v.sbp) AS sbp,AVG(v.dbp) AS dbp,AVG(v.spo2) AS spo2,
 COUNT(v.heart_rate) AS hr_n,COUNT(v.sbp) AS sbp_n,COUNT(v.dbp) AS dbp_n,COUNT(v.spo2) AS spo2_n
FROM public.af_bcr_cohort c LEFT JOIN mimiciv_derived.vitalsign v
 ON v.stay_id=c.stay_id AND v.charttime>=c.icu_intime AND v.charttime<c.prediction_time
GROUP BY c.subject_id,c.hadm_id,c.stay_id;
