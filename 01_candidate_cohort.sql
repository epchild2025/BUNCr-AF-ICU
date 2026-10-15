-- 01. 首次合格住院的 ICU 24h landmark 候选队列（不提前删 BUN/Cr）
DROP TABLE IF EXISTS public.af_bcr_candidate CASCADE;
CREATE TABLE public.af_bcr_candidate AS
WITH dx AS (
  SELECT a.subject_id,a.hadm_id,MIN(d.seq_num) AS af_seq_num
  FROM mimiciv_hosp.admissions a
  JOIN mimiciv_hosp.diagnoses_icd d ON a.hadm_id=d.hadm_id
  WHERE (d.icd_version=9 AND d.icd_code='42731')
     OR (d.icd_version=10 AND d.icd_code IN ('I48','I480','I481','I4811','I4819','I482','I4820','I4821','I489','I4891'))
  GROUP BY a.subject_id,a.hadm_id
), icu AS (
  SELECT *,ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime,stay_id) AS rn
  FROM mimiciv_icu.icustays
), qualified AS (
  SELECT p.subject_id,a.hadm_id,i.stay_id,p.gender,
    (p.anchor_age+EXTRACT(YEAR FROM a.admittime)::int-p.anchor_year)::int AS age,
    a.admittime,a.dischtime,a.deathtime,a.hospital_expire_flag AS hospital_mortality,
    a.insurance,a.marital_status,a.race,dx.af_seq_num,
    i.intime AS icu_intime,i.outtime AS icu_outtime,
    i.intime+INTERVAL '24 hours' AS prediction_time
  FROM dx JOIN mimiciv_hosp.admissions a ON dx.hadm_id=a.hadm_id
  JOIN mimiciv_hosp.patients p ON p.subject_id=a.subject_id
  JOIN icu i ON i.hadm_id=a.hadm_id AND i.rn=1
  WHERE (p.anchor_age+EXTRACT(YEAR FROM a.admittime)::int-p.anchor_year)>=65
    AND i.outtime>i.intime+INTERVAL '24 hours'
    AND a.dischtime>i.intime+INTERVAL '24 hours'
    AND (a.deathtime IS NULL OR a.deathtime>i.intime+INTERVAL '24 hours')
), ranked AS (
 SELECT *,ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime,hadm_id,stay_id) AS patient_rn FROM qualified
)
SELECT subject_id,hadm_id,stay_id,gender,age,admittime,dischtime,deathtime,
  hospital_mortality,insurance,marital_status,race,af_seq_num,
  icu_intime,icu_outtime,prediction_time
FROM ranked WHERE patient_rn=1;
CREATE UNIQUE INDEX ON public.af_bcr_candidate(stay_id);
