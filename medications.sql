DROP TABLE IF EXISTS public.eicu_af_bcr_medications;
CREATE TABLE public.eicu_af_bcr_medications AS
WITH meds AS (
 SELECT c.stay_id,lower(m.drugname) drug
 FROM public.eicu_af_bcr_cohort c JOIN public.medication m ON m.patientunitstayid=c.stay_id
 WHERE m.drugstartoffset<1440 AND (m.drugstopoffset IS NULL OR m.drugstopoffset>0)
 AND lower(coalesce(m.drugordercancelled,'no'))<>'yes'
 UNION ALL
 SELECT c.stay_id,lower(i.drugname) drug
 FROM public.eicu_af_bcr_cohort c JOIN public.infusiondrug i ON i.patientunitstayid=c.stay_id
 WHERE i.infusionoffset>=0 AND i.infusionoffset<1440
), a AS (
 SELECT stay_id,
 MAX((drug ~ '(warfarin|rivaroxaban|xarelto|dabigatran|pradaxa|apixaban|eliquis|edoxaban|heparin|enoxaparin)')::int) anticoagulant,
 MAX((drug ~ '(aspirin|clopidogrel|plavix|ticagrelor|brilinta|prasugrel)')::int) antiplatelet,
 MAX((drug ~ '(amiodarone|cordarone|pacerone)')::int) amiodarone,
 MAX((drug ~ '(bisoprolol|zebeta)')::int) bisoprolol,
 MAX((drug ~ '(metoprolol|lopressor|toprol)')::int) metoprolol,
 MAX((drug ~ '(sotalol|betapace)')::int) sotalol
 FROM meds GROUP BY stay_id
)
SELECT c.stay_id,c.hospital_stay_id,
 coalesce(a.anticoagulant,0) anticoagulant,coalesce(a.antiplatelet,0) antiplatelet,
 CASE WHEN a.anticoagulant=1 THEN 2 WHEN a.antiplatelet=1 THEN 1 ELSE 0 END med_status,
 coalesce(a.amiodarone,0) amiodarone,coalesce(a.bisoprolol,0) bisoprolol,
 coalesce(a.metoprolol,0) metoprolol,coalesce(a.sotalol,0) sotalol
FROM public.eicu_af_bcr_cohort c LEFT JOIN a USING(stay_id);

