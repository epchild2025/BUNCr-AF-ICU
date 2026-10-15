DROP TABLE IF EXISTS public.eicu_af_bcr_cohort;
CREATE TABLE public.eicu_af_bcr_cohort AS
WITH mapped AS (
 SELECT c.stay_id,l.labid,l.labresultoffset,l.labresultrevisedoffset,l.labresult,
 lower(trim(l.labname)) AS raw_lab_name,
 CASE WHEN lower(trim(l.labname)) IN ('bun','blood urea nitrogen','urea nitrogen') THEN 'bun'
 WHEN lower(trim(l.labname)) IN ('creatinine') THEN 'creatinine' END AS lab,
 l.labmeasurenamesystem AS lab_unit
 FROM public.eicu_af_bcr_candidate c JOIN public.lab l ON l.patientunitstayid=c.stay_id
 WHERE l.labresultoffset>=0 AND l.labresultoffset<1440
 AND l.labresultrevisedoffset<1440 AND l.labresult>0
 AND lower(trim(l.labname)) IN ('bun','blood urea nitrogen','urea nitrogen','creatinine')
), ranked AS (
 SELECT *,row_number() OVER(PARTITION BY stay_id,lab ORDER BY labresultoffset,labid) AS rn FROM mapped
), wide AS (
 SELECT stay_id,
 MAX(labresult) FILTER(WHERE lab='bun') AS bun,
 MAX(labresult) FILTER(WHERE lab='creatinine') AS creatinine,
 MAX(labresultoffset) FILTER(WHERE lab='bun') AS bun_offset,
 MAX(labresultoffset) FILTER(WHERE lab='creatinine') AS creatinine_offset,
 MAX(lab_unit) FILTER(WHERE lab='bun') AS bun_unit,
 MAX(lab_unit) FILTER(WHERE lab='creatinine') AS creatinine_unit
 FROM ranked WHERE rn=1 GROUP BY stay_id
)
SELECT c.*,w.bun,w.creatinine,round((w.bun/nullif(w.creatinine,0))::numeric,4) AS bcr,
 w.bun_offset,w.creatinine_offset,w.bun_unit,w.creatinine_unit,
 round((abs(w.bun_offset-w.creatinine_offset)/60.0)::numeric,2) AS lab_time_gap_hours
FROM public.eicu_af_bcr_candidate c JOIN wide w USING(stay_id)
WHERE w.bun IS NOT NULL AND w.creatinine IS NOT NULL;
CREATE UNIQUE INDEX eicu_af_bcr_cohort_stay_idx ON public.eicu_af_bcr_cohort(stay_id);
SELECT bun_unit,creatinine_unit, count(*) n FROM public.eicu_af_bcr_cohort GROUP BY 1,2 ORDER BY n DESC;
