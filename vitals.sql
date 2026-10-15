DROP TABLE IF EXISTS public.eicu_af_bcr_vitals;
CREATE TABLE public.eicu_af_bcr_vitals AS
SELECT c.stay_id,c.hospital_stay_id,
 AVG(v.heartrate) FILTER(WHERE v.heartrate BETWEEN 20 AND 250) hr,
 AVG(v.systemicsystolic) FILTER(WHERE v.systemicsystolic BETWEEN 40 AND 300) sbp,
 AVG(v.systemicdiastolic) FILTER(WHERE v.systemicdiastolic BETWEEN 20 AND 200) dbp,
 AVG(v.sao2) FILTER(WHERE v.sao2 BETWEEN 50 AND 100) spo2,
 COUNT(v.heartrate) FILTER(WHERE v.heartrate BETWEEN 20 AND 250) hr_n,
 COUNT(v.systemicsystolic) FILTER(WHERE v.systemicsystolic BETWEEN 40 AND 300) sbp_n,
 COUNT(v.systemicdiastolic) FILTER(WHERE v.systemicdiastolic BETWEEN 20 AND 200) dbp_n,
 COUNT(v.sao2) FILTER(WHERE v.sao2 BETWEEN 50 AND 100) spo2_n
FROM public.eicu_af_bcr_cohort c LEFT JOIN public.vitalperiodic v
 ON v.patientunitstayid=c.stay_id AND v.observationoffset>=0 AND v.observationoffset<1440
GROUP BY c.stay_id,c.hospital_stay_id;

