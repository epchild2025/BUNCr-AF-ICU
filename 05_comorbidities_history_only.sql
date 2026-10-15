-- 06. 合并症：仅已完成的历史住院 ICD，避免当前住院未来诊断
DROP TABLE IF EXISTS public.af_bcr_comorbidities;
CREATE TABLE public.af_bcr_comorbidities AS
WITH history AS (
 SELECT c.stay_id,d.icd_version,d.icd_code
 FROM public.af_bcr_cohort c JOIN mimiciv_hosp.admissions a
 ON a.subject_id=c.subject_id AND a.hadm_id<>c.hadm_id AND a.dischtime<c.icu_intime
 JOIN mimiciv_hosp.diagnoses_icd d ON d.hadm_id=a.hadm_id
), agg AS (
 SELECT stay_id,
 MAX(CASE WHEN (icd_version=9 AND (icd_code LIKE '428%' OR icd_code IN ('39891','40201','40211','40291','40401','40411','40491','40493')))
 OR (icd_version=10 AND (icd_code LIKE 'I50%' OR icd_code IN ('I110','I130','I132'))) THEN 1 ELSE 0 END) AS hf,
 MAX(CASE WHEN (icd_version=9 AND (icd_code LIKE '401%' OR icd_code LIKE '402%' OR icd_code LIKE '403%' OR icd_code LIKE '404%' OR icd_code LIKE '405%'))
 OR (icd_version=10 AND (icd_code LIKE 'I10%' OR icd_code LIKE 'I11%' OR icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' OR icd_code LIKE 'I15%')) THEN 1 ELSE 0 END) AS htn,
 MAX(CASE WHEN (icd_version=9 AND (icd_code LIKE '249%' OR icd_code LIKE '250%'))
 OR (icd_version=10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%')) THEN 1 ELSE 0 END) AS diabetes,
 MAX(CASE WHEN (icd_version=9 AND (icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code='496'))
 OR (icd_version=10 AND icd_code LIKE 'J44%') THEN 1 ELSE 0 END) AS copd,
 MAX(CASE WHEN (icd_version=9 AND (icd_code LIKE '433%' OR icd_code LIKE '434%' OR icd_code LIKE '435%' OR icd_code='V1254'))
 OR (icd_version=10 AND (icd_code LIKE 'I63%' OR icd_code LIKE 'G45%' OR icd_code LIKE 'I693%' OR icd_code='Z8673')) THEN 1 ELSE 0 END) AS stroke_tia,
 MAX(CASE WHEN (icd_version=9 AND (icd_code LIKE '410%' OR icd_code LIKE '440%' OR icd_code='412' OR icd_code='4439'))
 OR (icd_version=10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I25%' OR icd_code LIKE 'I70%' OR icd_code LIKE 'I73%')) THEN 1 ELSE 0 END) AS vascular_disease,
 MAX(CASE WHEN (icd_version=9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%' OR icd_code='5789'))
 OR (icd_version=10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' OR icd_code='K922')) THEN 1 ELSE 0 END) AS prior_bleeding
 FROM history GROUP BY stay_id
)
SELECT c.subject_id,c.hadm_id,c.stay_id,COALESCE(a.hf,0) AS hf,
 COALESCE(a.htn,0) AS htn,COALESCE(a.diabetes,0) AS diabetes,
 COALESCE(a.copd,0) AS copd,COALESCE(a.stroke_tia,0) AS stroke_tia,
 COALESCE(a.vascular_disease,0) AS vascular_disease,
 COALESCE(a.prior_bleeding,0) AS prior_bleeding
FROM public.af_bcr_cohort c LEFT JOIN agg a USING(stay_id);
