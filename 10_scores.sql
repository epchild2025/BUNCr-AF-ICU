DROP TABLE IF EXISTS public.af_bcr_scores;

CREATE TABLE public.af_bcr_scores AS

WITH sofa_selected AS (
    SELECT DISTINCT ON (c.stay_id)
        c.stay_id,
        s.sofa_24hours AS sofa_score,
        s.hr AS sofa_hr,
        s.starttime AS sofa_starttime,
        s.endtime AS sofa_endtime

    FROM mimiciv_derived.sofa s

    JOIN public.af_bcr_cohort c
        ON s.stay_id = c.stay_id

    WHERE s.endtime <= c.prediction_time

    ORDER BY
        c.stay_id,
        s.endtime DESC,
        s.hr DESC
)

SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,

    a.apsiii,
    o.oasis,
    sa.sapsii,

    sf.sofa_score,
    sf.sofa_hr,
    sf.sofa_starttime,
    sf.sofa_endtime

FROM public.af_bcr_cohort c

LEFT JOIN mimiciv_derived.apsiii a
    ON c.stay_id = a.stay_id

LEFT JOIN mimiciv_derived.oasis o
    ON c.stay_id = o.stay_id

LEFT JOIN mimiciv_derived.sapsii sa
    ON c.stay_id = sa.stay_id

LEFT JOIN sofa_selected sf
    ON c.stay_id = sf.stay_id;
