-- 08. 药物：处方起止时间与 ICU 0-24h 重叠
DROP TABLE IF EXISTS public.af_bcr_medications;
CREATE TABLE public.af_bcr_medications AS
WITH meds AS (
 SELECT c.stay_id,lower(p.drug) AS drug
 FROM public.af_bcr_cohort c JOIN mimiciv_hosp.prescriptions p
 ON p.hadm_id=c.hadm_id AND p.subject_id=c.subject_id
 WHERE p.drug IS NOT NULL AND p.starttime<c.prediction_time
 AND (p.stoptime IS NULL OR p.stoptime>c.icu_intime)
), agg AS (
 SELECT stay_id,
 MAX(CASE WHEN drug LIKE '%warfarin%' OR drug LIKE '%rivaroxaban%' OR drug LIKE '%xarelto%'
 OR drug LIKE '%dabigatran%' OR drug LIKE '%pradaxa%' OR drug LIKE '%apixaban%'
 OR drug LIKE '%eliquis%' OR drug LIKE '%edoxaban%' THEN 1 ELSE 0 END) AS anticoagulant,
 MAX(CASE WHEN drug LIKE '%aspirin%' OR drug LIKE '%clopidogrel%' OR drug LIKE '%plavix%'
 OR drug LIKE '%ticagrelor%' OR drug LIKE '%brilinta%' OR drug LIKE '%prasugrel%' THEN 1 ELSE 0 END) AS antiplatelet,
 MAX(CASE WHEN drug LIKE '%amiodarone%' OR drug LIKE '%cordarone%' OR drug LIKE '%pacerone%' THEN 1 ELSE 0 END) AS amiodarone,
 MAX(CASE WHEN drug LIKE '%bisoprolol%' OR drug LIKE '%zebeta%' THEN 1 ELSE 0 END) AS bisoprolol,
 MAX(CASE WHEN drug LIKE '%metoprolol%' OR drug LIKE '%lopressor%' OR drug LIKE '%toprol%' THEN 1 ELSE 0 END) AS metoprolol,
 MAX(CASE WHEN drug LIKE '%sotalol%' OR drug LIKE '%betapace%' THEN 1 ELSE 0 END) AS sotalol
 FROM meds GROUP BY stay_id
)
SELECT c.subject_id,c.hadm_id,c.stay_id,
 COALESCE(a.anticoagulant,0) AS anticoagulant,
 COALESCE(a.antiplatelet,0) AS antiplatelet,
 CASE WHEN a.anticoagulant=1 THEN 2 WHEN a.antiplatelet=1 THEN 1 ELSE 0 END AS med_status,
 COALESCE(a.amiodarone,0) AS amiodarone,
 COALESCE(a.bisoprolol,0) AS bisoprolol,
 COALESCE(a.metoprolol,0) AS metoprolol,
 COALESCE(a.sotalol,0) AS sotalol
FROM public.af_bcr_cohort c LEFT JOIN agg a USING(stay_id);
