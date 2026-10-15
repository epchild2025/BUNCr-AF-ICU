"""Prediction and explanation helpers for the fixed manuscript RF model."""
from pathlib import Path
import hashlib
import pickle

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier

FEATURE_NAMES = [
    'mech_vent', 'crrt_24h', 'med_status', 'age', 'ucr', 'charlson_score',
    'apsiii', 'oasis', 'sapsii', 'sofa_score', 'hr', 'spo2', 'rbc', 'wbc',
    'platelets', 'glucose',
]
THRESHOLD = 0.21747200428484978
MODEL_SHA256 = '8fe2acc54c4d9e79218b4fa9b45150eb9344120c1016d475a1f8dcbe6f2b4ba7'
MODEL_PATH = Path(__file__).resolve().with_name('rf_model.pkl')


def load_model():
    raw = MODEL_PATH.read_bytes()
    if hashlib.sha256(raw).hexdigest() != MODEL_SHA256:
        raise ValueError('The model file does not match the validated random forest.')
    model = pickle.loads(raw)
    if not isinstance(model, RandomForestClassifier):
        raise ValueError('A random forest classifier is required.')
    if list(model.feature_names_in_) != FEATURE_NAMES:
        raise ValueError('Model feature names or their order do not match the app.')
    if list(model.classes_) != [0, 1]:
        raise ValueError('Expected outcome coding: 0 = survival, 1 = in-hospital death.')
    return model


def input_frame(values):
    if set(values) != set(FEATURE_NAMES):
        raise ValueError('Please supply all 16 required model inputs.')
    frame = pd.DataFrame([[values[name] for name in FEATURE_NAMES]], columns=FEATURE_NAMES, dtype=float)
    if not np.isfinite(frame.to_numpy()).all():
        raise ValueError('All inputs must be finite numbers.')
    for name in ['mech_vent', 'crrt_24h']:
        if values[name] not in (0, 1):
            raise ValueError(f'{name} must be 0 or 1.')
    if values['med_status'] not in (0, 1, 2):
        raise ValueError('Medication status must be 0, 1, or 2.')
    if values['age'] < 65:
        raise ValueError('The model population is aged 65 years or older.')
    if not 0 <= values['spo2'] <= 100:
        raise ValueError('SpO2 must be between 0 and 100%.')
    if (frame.to_numpy() < 0).any() or values['ucr'] <= 0 or values['glucose'] <= 0:
        raise ValueError('Inputs must be nonnegative; BUN/Cr and glucose must be positive.')
    return frame


def death_probability(model, frame):
    if list(frame.columns) != FEATURE_NAMES:
        raise ValueError('Input feature order does not match the model.')
    positive_index = list(model.classes_).index(1)
    return model.predict_proba(frame)[:, positive_index]


def positive_class_explanation(model, frame):
    import shap
    explainer = shap.TreeExplainer(model)
    explanation = explainer(frame, check_additivity=True)
    if explanation.values.ndim != 3:
        raise ValueError('Expected a SHAP explanation with one output per RF class.')
    positive = explanation[:, :, list(model.classes_).index(1)]
    reconstructed = np.asarray(positive.base_values) + positive.values.sum(axis=1)
    if not np.allclose(reconstructed, death_probability(model, frame), atol=1e-6, rtol=1e-6):
        raise ValueError('SHAP contributions do not reconstruct the death probability.')
    return positive
