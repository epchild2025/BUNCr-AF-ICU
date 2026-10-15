DROP TABLE IF EXISTS public.eicu_af_bcr_ventilation;
CREATE TABLE public.eicu_af_bcr_ventilation AS
WITH a AS (
 SELECT c.stay_id,
 MAX(CASE WHEN (lower(coalesce(r.airwaytype,'')) LIKE '%ett%' OR lower(coalesce(r.airwaytype,'')) LIKE '%tracheostom%')
 AND r.ventstartoffset<1440 AND (r.ventendoffset IS NULL OR r.ventendoffset>0)
 THEN 1 ELSE 0 END) mech_vent
 FROM public.eicu_af_bcr_cohort c LEFT JOIN public.respiratorycare r ON r.patientunitstayid=c.stay_id
 GROUP BY c.stay_id
)
SELECT c.stay_id,c.hospital_stay_id,coalesce(a.mech_vent,0) AS mech_vent
FROM public.eicu_af_bcr_cohort c LEFT JOIN a USING(stay_id);

