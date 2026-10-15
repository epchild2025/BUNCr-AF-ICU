DROP TABLE IF EXISTS public.eicu_af_bcr_labs;
CREATE TABLE public.eicu_af_bcr_labs AS
WITH m AS (
 SELECT c.stay_id,l.labid,l.labresultoffset,l.labresult,
 CASE lower(trim(l.labname))
 WHEN 'hgb' THEN 'hemoglobin' WHEN 'hemoglobin' THEN 'hemoglobin'
 WHEN 'rbc' THEN 'rbc' WHEN 'wbc x 1000' THEN 'wbc' WHEN 'wbc' THEN 'wbc'
 WHEN 'platelets x 1000' THEN 'platelets' WHEN 'platelets' THEN 'platelets'
 WHEN 'ast (sgot)' THEN 'ast' WHEN 'ast' THEN 'ast'
 WHEN 'alt (sgpt)' THEN 'alt' WHEN 'alt' THEN 'alt'
 WHEN 'total bilirubin' THEN 'tbil' WHEN 'bilirubin total' THEN 'tbil'
 WHEN 'pt' THEN 'pt' WHEN 'inr' THEN 'inr' WHEN 'pt - inr' THEN 'inr'
 WHEN 'ptt' THEN 'aptt' WHEN 'aptt' THEN 'aptt'
 WHEN 'anion gap' THEN 'anion_gap' WHEN 'glucose' THEN 'glucose' END AS lab
 FROM public.eicu_af_bcr_cohort c JOIN public.lab l ON l.patientunitstayid=c.stay_id
 WHERE l.labresultoffset>=0 AND l.labresultoffset<1440 AND l.labresultrevisedoffset<1440
 AND l.labresult IS NOT NULL
), r AS (
 SELECT *,row_number() OVER(PARTITION BY stay_id,lab ORDER BY labresultoffset,labid) rn FROM m WHERE lab IS NOT NULL
), w AS (
 SELECT stay_id,
 MAX(labresult) FILTER(WHERE lab='hemoglobin') hemoglobin,
 MAX(labresult) FILTER(WHERE lab='rbc') rbc,
 MAX(labresult) FILTER(WHERE lab='wbc') wbc,
 MAX(labresult) FILTER(WHERE lab='platelets') platelets,
 MAX(labresult) FILTER(WHERE lab='ast') ast,
 MAX(labresult) FILTER(WHERE lab='alt') alt,
 MAX(labresult) FILTER(WHERE lab='tbil') tbil,
 MAX(labresult) FILTER(WHERE lab='pt') pt,
 MAX(labresult) FILTER(WHERE lab='inr') inr,
 MAX(labresult) FILTER(WHERE lab='aptt') aptt,
 MAX(labresult) FILTER(WHERE lab='anion_gap') anion_gap,
 MAX(labresult) FILTER(WHERE lab='glucose') glucose
 FROM r WHERE rn=1 GROUP BY stay_id
)
SELECT c.stay_id,c.hospital_stay_id,w.hemoglobin,w.rbc,w.wbc,w.platelets,
w.ast,w.alt,w.tbil,w.pt,w.inr,w.aptt,w.anion_gap,w.glucose
FROM public.eicu_af_bcr_cohort c LEFT JOIN w USING(stay_id);
