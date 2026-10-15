-- 03. 其他实验室指标：首次 0-24h，结果在 landmark 前可获得
DROP TABLE IF EXISTS public.af_bcr_labs;
CREATE TABLE public.af_bcr_labs AS
WITH mapped AS (
 SELECT c.stay_id,l.valuenum,l.charttime,l.labevent_id,l.valueuom,
   CASE
    WHEN itemid=51222 THEN 'hemoglobin' WHEN itemid=51279 THEN 'rbc'
    WHEN itemid=51301 THEN 'wbc' WHEN itemid=51265 THEN 'platelets'
    WHEN itemid IN (50878,53088) THEN 'ast' WHEN itemid IN (50861,53084) THEN 'alt'
    WHEN itemid IN (50885,53089) THEN 'tbil'
    WHEN itemid IN (51274,52921) THEN 'pt' WHEN itemid=51237 THEN 'inr'
    WHEN itemid IN (51275,52923) THEN 'aptt'
    WHEN itemid=50868 THEN 'anion_gap'
    WHEN itemid IN (50931,50809) THEN 'glucose' END AS lab
 FROM public.af_bcr_cohort c
 JOIN mimiciv_hosp.labevents l ON l.subject_id=c.subject_id AND l.hadm_id=c.hadm_id
 WHERE itemid IN (51222,51279,51301,51265,50878,53088,50861,53084,
                 50885,53089,51274,52921,51237,51275,52923,50868,50931,50809)
  AND l.valuenum IS NOT NULL AND l.charttime>=c.icu_intime AND l.charttime<c.prediction_time
  AND (l.storetime IS NULL OR l.storetime<c.prediction_time)
), first_lab AS (
 SELECT *,ROW_NUMBER() OVER(PARTITION BY stay_id,lab ORDER BY charttime,labevent_id) AS rn FROM mapped
), wide AS (
 SELECT stay_id,
 MAX(valuenum) FILTER(WHERE lab='hemoglobin') AS hemoglobin,
 MAX(valuenum) FILTER(WHERE lab='rbc') AS rbc,
 MAX(valuenum) FILTER(WHERE lab='wbc') AS wbc,
 MAX(valuenum) FILTER(WHERE lab='platelets') AS platelets,
 MAX(valuenum) FILTER(WHERE lab='ast') AS ast,
 MAX(valuenum) FILTER(WHERE lab='alt') AS alt,
 MAX(valuenum) FILTER(WHERE lab='tbil') AS tbil,
 MAX(valuenum) FILTER(WHERE lab='pt') AS pt,
 MAX(valuenum) FILTER(WHERE lab='inr') AS inr,
 MAX(valuenum) FILTER(WHERE lab='aptt') AS aptt,
 MAX(valuenum) FILTER(WHERE lab='anion_gap') AS anion_gap,
 MAX(valuenum) FILTER(WHERE lab='glucose') AS glucose
 FROM first_lab WHERE rn=1 GROUP BY stay_id
)
SELECT c.subject_id,c.hadm_id,c.stay_id,w.hemoglobin,w.rbc,w.wbc,w.platelets,
 w.ast,w.alt,w.tbil,w.pt,w.inr,w.aptt,w.anion_gap,w.glucose
FROM public.af_bcr_cohort c LEFT JOIN wide w USING(stay_id);
