"""SAFE-ICU: fixed random forest for in-hospital mortality."""
from io import BytesIO
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import shap
import streamlit as st
from rf_predictor import MODEL_SHA256, THRESHOLD, death_probability, input_frame, load_model, positive_class_explanation

st.set_page_config(page_title='SAFE-ICU Predictor', layout='wide')
plt.rcParams['svg.fonttype'] = 'none'

@st.cache_resource
def cached_model(model_sha256):
    if model_sha256 != MODEL_SHA256:
        raise ValueError('Model cache identity is out of date.')
    return load_model()

st.title('SAFE-ICU Predictor')
st.subheader('In-hospital mortality prediction for older ICU patients with atrial fibrillation')
st.markdown('Random forest model for patients aged **65 years or older** who remain eligible at **24 hours after ICU admission**.')
st.caption('Use the study-defined first-day inputs. This research prediction does not define a treatment target.')
try:
    model = cached_model(MODEL_SHA256)
except Exception as exc:
    st.error(f'The random forest model could not be loaded: {exc}')
    st.stop()

yes_no = {0: 'No', 1: 'Yes'}
medication_options = {0: 'Neither', 1: 'Antiplatelet only', 2: 'Anticoagulant, with or without antiplatelet'}
values = {}
with st.form('patient_inputs'):
    left, right = st.columns(2)
    with left:
        st.subheader('Patient and first-day treatment')
        values['age'] = st.number_input('Age (years)', min_value=65, max_value=120, value=78, key='age')
        values['mech_vent'] = st.selectbox('Mechanical ventilation within the first 24 hours', [0, 1], format_func=yes_no.get, key='mech_vent')
        values['crrt_24h'] = st.selectbox('Renal replacement therapy within the first 24 hours', [0, 1], format_func=yes_no.get, key='crrt_24h')
        values['med_status'] = st.selectbox('Antithrombotic prescriptions overlapping the first 24 hours', [0, 1, 2], format_func=medication_options.get, key='med_status')
        st.subheader('Severity scores')
        values['charlson_score'] = st.number_input('Charlson comorbidity score', min_value=0, value=6, key='charlson_score')
        values['apsiii'] = st.number_input('APS III score', min_value=0, value=44, key='apsiii')
        values['oasis'] = st.number_input('OASIS score', min_value=0, value=34, key='oasis')
        values['sapsii'] = st.number_input('SAPS II score', min_value=0, value=40, key='sapsii')
        values['sofa_score'] = st.number_input('First-day SOFA score', min_value=0, max_value=24, value=4, key='sofa_score')
    with right:
        st.subheader('First-day measurements')
        st.caption('Laboratory values: first eligible result within ICU hours 0–24. BUN and creatinine must both be measured in mg/dL.')
        values['ucr'] = st.number_input('BUN/creatinine ratio', min_value=0.0001, value=20.8108, step=0.1, format='%.4f', key='ucr')
        values['rbc'] = st.number_input('Red blood cell count (10¹²/L)', min_value=0.0, value=3.4, step=0.1, key='rbc')
        values['wbc'] = st.number_input('White blood cell count (10⁹/L)', min_value=0.0, value=10.9, step=0.1, key='wbc')
        values['platelets'] = st.number_input('Platelet count (10⁹/L)', min_value=0.0, value=174.0, step=1.0, key='platelets')
        values['glucose'] = st.number_input('Glucose (mg/dL)', min_value=0.01, value=130.0, step=1.0, key='glucose')
        st.caption('Vital signs: means within ICU hours 0–24.')
        values['hr'] = st.number_input('Mean heart rate (beats/min)', min_value=0.0, value=81.88, step=1.0, key='hr')
        values['spo2'] = st.number_input('Mean SpO2 (%)', min_value=0.0, max_value=100.0, value=97.4, step=0.1, key='spo2')
    submitted = st.form_submit_button('Predict')

if submitted:
    try:
        frame = input_frame(values)
        probability = float(death_probability(model, frame)[0])
    except ValueError as exc:
        st.error(str(exc))
        st.stop()
    st.subheader('Assessment results')
    col1, col2 = st.columns(2)
    col1.metric('Estimated in-hospital mortality probability', f'{probability:.2%}')
    col2.metric('Model risk category', 'Higher predicted risk' if probability >= THRESHOLD else 'Lower predicted risk')
    st.caption(f'Classification threshold: {THRESHOLD:.4%}, selected by the best F1 score in internal validation. This probability is the original random forest output; no external-cohort recalibration is applied.')
    st.markdown('The category summarizes the model output. It does not prescribe monitoring intensity, treatment, or a target BUN/Cr ratio.')
    st.subheader('Individual prediction explanation')
    try:
        explanation = positive_class_explanation(model, frame)
        shap.plots.waterfall(explanation[0], max_display=16, show=False)
        fig = plt.gcf()
        fig.set_size_inches(10, 8)
        st.pyplot(fig)
        st.caption('Positive SHAP values increase the predicted probability of in-hospital death relative to the model baseline; negative values decrease it. Contributions describe this prediction, not causal effects.')
        svg = BytesIO()
        fig.savefig(svg, format='svg', bbox_inches='tight')
        st.download_button('Download editable SHAP figure (SVG)', svg.getvalue(), file_name='SAFE_ICU_RF_SHAP.svg', mime='image/svg+xml', on_click='ignore')
        plt.close(fig)
    except Exception as exc:
        st.warning(f'The prediction is available, but its SHAP explanation could not be generated: {exc}')
