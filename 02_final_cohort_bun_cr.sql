-- 02. 核心暴露：首次 ICU 0-24h BUN 与 Cr，两者任一缺失则不进入最终队列。
-- 所有后续模块必须使用 public.af_bcr_cohort，不再使用 candidate。
DROP TABLE IF EXISTS public.af_bcr_cohort CASCADE;
CREATE TABLE public.af_bcr_cohort AS
WITH first_two AS (
 SELECT c.stay_id,
   CASE WHEN l.itemid IN (51006,52647) THEN 'bun' ELSE 'creatinine' END AS lab,
   l.valuenum,l.charttime,l.storetime,l.valueuom,
   ROW_NUMBER() OVER (
     PARTITION BY c.stay_id,CASE WHEN l.itemid IN (51006,52647) THEN 'bun' ELSE 'creatinine' END
     ORDER BY l.charttime,l.labevent_id
   ) AS rn
 FROM public.af_bcr_candidate c
 JOIN mimiciv_hosp.labevents l ON l.subject_id=c.subject_id AND l.hadm_id=c.hadm_id
 WHERE l.itemid IN (51006,52647,50912,52546)
   AND l.valuenum IS NOT NULL AND l.valuenum>0
   AND l.charttime>=c.icu_intime AND l.charttime<c.prediction_time
   -- 可获得性约束：保留在预测时点前存储的结果
   AND (l.storetime IS NULL OR l.storetime<c.prediction_time)
), wide AS (
 SELECT stay_id,
   MAX(valuenum) FILTER(WHERE lab='bun') AS bun,
   MAX(valuenum) FILTER(WHERE lab='creatinine') AS creatinine,
   MAX(charttime) FILTER(WHERE lab='bun') AS bun_time,
   MAX(charttime) FILTER(WHERE lab='creatinine') AS creatinine_time,
   MAX(valueuom) FILTER(WHERE lab='bun') AS bun_unit,
   MAX(valueuom) FILTER(WHERE lab='creatinine') AS creatinine_unit
 FROM first_two WHERE rn=1 GROUP BY stay_id
)
SELECT c.*,w.bun,w.creatinine,
 ROUND((w.bun/NULLIF(w.creatinine,0))::numeric,4) AS bcr,
 w.bun_time,w.creatinine_time,w.bun_unit,w.creatinine_unit,
 ROUND((ABS(EXTRACT(EPOCH FROM (w.bun_time-w.creatinine_time)))/3600.0)::numeric,2)
   AS lab_time_gap_hours
FROM public.af_bcr_candidate c JOIN wide w ON w.stay_id=c.stay_id
WHERE w.bun IS NOT NULL AND w.creatinine IS NOT NULL AND w.creatinine>0;
CREATE UNIQUE INDEX ON public.af_bcr_cohort(stay_id);
-- 自检：仅当 unit 与原定 mg/dL 相符时，可把 bcr 直接作为 BUN/Cr mg/dL 比值。
SELECT COUNT(*) AS final_n,COUNT(DISTINCT stay_id) AS unique_stays,
 SUM(hospital_mortality) AS deaths,ROUND(AVG(hospital_mortality)*100,2) AS mortality_pct,
 MIN(bcr) AS bcr_min,MAX(bcr) AS bcr_max
FROM public.af_bcr_cohort;
SELECT bun_unit,creatinine_unit,COUNT(*) AS n FROM public.af_bcr_cohort
GROUP BY bun_unit,creatinine_unit ORDER BY n DESC;
