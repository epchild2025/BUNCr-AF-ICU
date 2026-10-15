DROP TABLE IF EXISTS public.eicu_af_bcr_comorbidities;
CREATE TABLE public.eicu_af_bcr_comorbidities AS
WITH hist AS (
 SELECT c.stay_id,lower(concat_ws(' ',ph.pasthistorypath,ph.pasthistoryvalue,ph.pasthistoryvaluetext)) AS txt
 FROM public.eicu_af_bcr_cohort c JOIN public.pasthistory ph ON ph.patientunitstayid=c.stay_id
 WHERE ph.pasthistoryenteredoffset <1440
 AND lower(coalesce(ph.pasthistoryvalue,'')) NOT IN ('no','no health problems','not performed','not obtainable')
), a AS (
 SELECT stay_id,
 MAX((txt ~ '(heart failure|congestive heart failure|chf)')::int) hf,
 MAX((txt ~ '(hypertension|high blood pressure)')::int) htn,
 MAX((txt ~ '(diabetes|insulin dependent|non-insulin dependent)')::int) diabetes,
 MAX((txt ~ '(copd|chronic obstructive|emphysema)')::int) copd,
 MAX((txt ~ '(stroke|cerebrovascular accident|\btia\b|transient ischemic)')::int) stroke_tia,
 MAX((txt ~ '(peripheral vascular|coronary artery disease|myocardial infarction|\bpvd\b)')::int) vascular_disease,
 MAX((txt ~ '(gastrointestinal bleed|gi bleed|intracranial hemorrhage|prior bleeding)')::int) prior_bleeding
 FROM hist GROUP BY stay_id
)
SELECT c.stay_id,c.hospital_stay_id,
 a.hf,a.htn,a.diabetes,a.copd,a.stroke_tia,a.vascular_disease,a.prior_bleeding,
 CASE WHEN a.stay_id IS NULL THEN 0 ELSE 1 END AS past_history_documented
FROM public.eicu_af_bcr_cohort c LEFT JOIN a USING(stay_id);

