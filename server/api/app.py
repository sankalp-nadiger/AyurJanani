from flask import Flask, request, jsonify
import joblib
import numpy as np
import pandas as pd
import os
import requests
from dotenv import load_dotenv
load_dotenv()
from flask_cors import CORS
from datetime import datetime
from typing import Dict, List, Optional, Union
from sklearn.feature_extraction import DictVectorizer

from supabase import create_client, Client

app = Flask(__name__)
CORS(app)

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")
OLLAMA_MODEL_ID = os.environ.get("OLLAMA_MODEL_ID")
OLLAMA_API_HOST = os.environ.get("OLLAMA_API_HOST", "http://localhost:11434")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise ValueError("Missing SUPABASE_URL or SUPABASE_KEY environment variables")

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# Load ML Models
MODEL_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'models')

def load_model_safely(model_path: str, error_msg: str) -> Optional[object]:
    """Safely load a machine learning model with error handling."""
    try:
        if not os.path.exists(model_path):
            print(f"Warning: Model file not found at {model_path}")
            print(f"Impact: {error_msg}")
            print(f"Solution: Ensure model file is placed at {model_path}")
            return None
        
        model = joblib.load(model_path)
        print(f"Successfully loaded model from {model_path}")
        return model
    except Exception as e:
        print(f"Warning: Failed to load {model_path}: {str(e)}")
        print(f"Impact: {error_msg}")
        print(f"Solution: Check model file format and permissions")
        return None

# Load existing models from current location
maternal_model = joblib.load("finalized_maternal_model.sav")
maternal_scaler = joblib.load("scaleX.pkl")
fetal_model = joblib.load("fetal_health_model.sav")
fetal_scaler = joblib.load("scaleX1.pkl")

# Load new Ayurvedic models from models directory
symptom_classifier = load_model_safely(
    os.path.join(MODEL_PATH, 'ayurvedic/symptom_classifier_model.pkl'),
    'Symptom classification may be limited'
)

symptom_risk_model = load_model_safely(
    os.path.join(MODEL_PATH, 'ayurvedic/symptom_risk_model.pkl'),
    'Risk prediction may be limited'
)

remedy_model = load_model_safely(
    os.path.join(MODEL_PATH, 'ayurvedic/remedy_model.pkl'),
    'Remedy suggestions may be limited')

# Custom chat function to replace ollama-python client
def chat(model, messages):
    """
    Send a chat request to Ollama API using the requests library
    """
    try:
        response = requests.post(
            f"{OLLAMA_API_HOST}/api/chat",
            json={"model": model, "messages": messages}
        )
        
        result = response.json()
        # Format response to match original ollama-python structure
        class DotDict(dict):
            """Dot notation access to dictionary attributes"""
            __getattr__ = dict.get
            __setattr__ = dict.__setitem__
            __delattr__ = dict.__delitem__
            
        result_obj = DotDict(result)
        result_obj.message = DotDict(result.get("message", {}))
        return result_obj
    except Exception as e:
        print(f"Error in chat function: {str(e)}")
        raise

# Utility function for token validation
def validate_token(request) -> tuple[Optional[Dict], Optional[str]]:
    """Validate the authorization token and return user data or error."""
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        return None, 'No valid token provided'
    
    token = auth_header.split(' ')[1]
    try:
        user_data = supabase.auth.get_user(token)
        if not user_data or not user_data.user:
            return None, 'Invalid token'
        return user_data, None
    except Exception:
        return None, 'Failed to validate token'

@app.route("/create_doctor_profile", methods=["POST"])
def create_doctor_profile():
    '''Simple endpoint for us to dump some data into a table'''
    try:
        data = request.json
        doctor_data = {
            'name': data.get('name'),
            'phone': data.get('phone'),
            'specialty': data.get('specialty'),
            'location': data.get('location'),
            'profile_image_url': data.get('profile_image_url'),
        }

        result = supabase.table('doctors').upsert(doctor_data).execute()
        
        return jsonify({"message": "Doctor profile created successfully", "data": result.data}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/predict_maternal", methods=["POST"])
def predict_maternal():
    try:
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return {'error': 'No valid token provided'}, 401
        
        token = auth_header.split(' ')[1]

        user_data = supabase.auth.get_user(token)
        print("FREE TOKEN", token)

        if not user_data:
            return {'error': 'Invalid token'}, 401

        data = request.json
        features = [
            float(data["age"]),
            float(data["systolic_bp"]),
            float(data["diastolic_bp"]),
            float(data["blood_glucose"]),
            float(data["body_temp"]),
            float(data["heart_rate"])
        ]
        features = np.array(features).reshape(1, -1)
        scaled_features = maternal_scaler.transform(features)
        prediction = maternal_model.predict(scaled_features)
        risk_mapping = {0: "Normal", 1: "Suspect", 2: "Pathological"}
        risk_level = risk_mapping[int(prediction[0])]

        # Insert into vitals table   
        vital_data = {
            'UID': user_data.user.id,
            'systolic_bp': data["systolic_bp"],
            'diastolic_bp': data["diastolic_bp"],
            'blood_glucose': data["blood_glucose"],
            'body_temp': data["body_temp"],
            'heart_rate': data["heart_rate"],
            'prediction': int(prediction[0])
        }
        result = supabase.table('vitals').insert(vital_data).execute()

        return jsonify({"prediction": risk_level})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/predict_fetal", methods=["POST"])
def predict_fetal():
    try:
        # Validate Authorization Header
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({'error': 'No valid token provided'}), 401

        token = auth_header.split(' ')[1]
        
        # Validate Token & Get User Data
        try:
            user_data = supabase.auth.get_user(token)
            if not user_data or not user_data.user:
                return jsonify({'error': 'Invalid token'}), 401
        except Exception:
            return jsonify({'error': 'Failed to validate token'}), 401

        # Parse Input Data
        data = request.get_json()
        if not data or "features" not in data:
            return jsonify({'error': 'Missing required feature data'}), 400

        # Ensure feature list has correct length
        features = np.array(data["features"], dtype=float)
        expected_feature_length = 15  # Adjust as needed
        if features.shape[0] != expected_feature_length:
            return jsonify({'error': f'Invalid feature length, expected {expected_feature_length}'}), 400
        
        features = features.reshape(1, -1)

        # Scale features
        try:
            scaled_features = scaler.transform(features)
        except Exception as e:
            return jsonify({'error': f'Feature scaling failed: {str(e)}'}), 500

        # Make Prediction
        try:
            prediction = int(model.predict(scaled_features)[0])  # Ensure Python int
        except Exception as e:
            return jsonify({'error': f'Prediction failed: {str(e)}'}), 500

        # Map prediction to health status
        health_status = {1: "Normal", 2: "Suspect", 3: "Pathological"}
        prediction_result = health_status.get(prediction, "Unknown")

        # Define Feature Names
        feature_names = [
            'baseline_value', 'accelerations', 'fetal_movement', 'uterine_contractions',
            'light_decelerations', 'severe_decelerations', 'prolonged_decelerations',
            'abnormal_short_term_variability', 'mean_value_of_short_term_variability',
            'percentage_of_time_with_abnormal_long_term_variability', 'mean_value_of_long_term_variability',
            'histogram_width', 'histogram_min', 'histogram_max', 'histogram_number_of_peaks'
        ]

        # Map features to dictionary and ensure all values are Python types
        feature_dict = {k: float(v) for k, v in zip(feature_names, features.flatten())}

        # Prepare data for Supabase
        ctg_data = {
            'UID': user_data.user.id,
            **feature_dict,
            'prediction': prediction
        }

        # Insert Data into Supabase
        try:
            supabase.table('ctg').insert(ctg_data).execute()
        except Exception as e:
            return jsonify({'error': f'Database insert failed: {str(e)}'}), 500

        return jsonify({"prediction": prediction, "status": prediction_result})

    except Exception as e:
        return jsonify({"error": f"Unexpected error: {str(e)}"}), 500

@app.route("/diet_plan", methods=["POST"])
def pregnancy_diet():
    try:
        data = request.json

        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return {'error': 'No valid token provided'}, 401
        
        token = auth_header.split(' ')[1]

        user_data = supabase.auth.get_user(token)

        if not user_data:
            return {'error': 'Invalid token'}, 401
        
        prompt = f"You are a professional dietician and nutritionist. You suggest excellent diet plans for pregnant women that look after their well being and growth. You will now suggest a diet plan for a {data['trimester']} trimester pregnant woman weighing about {data['weight']} kg, who is feeling {data['health_conditions']} and has strict dietary preferences as follows: {data['dietary_preference']}. Do not suggest any foods that can cause harm or go against the dietary preferences. Suggest both a vegetarian only and a non-vegetarian diet plan separately for her and just give the plan."

        response = chat(model=OLLAMA_MODEL_ID, messages=[
            {'role':'user','content':prompt}
        ])

        # Store the diet plan in the database
        diet_data = {
            'UID': user_data.user.id,
            'diet_plan': response.message.content # Stored as markdown
        }

        return jsonify({"diet_plan": response.message.content})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    
@app.route('/chat', methods=['GET'])
def chatbot_get():
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        return {'error': 'No valid token provided'}, 401
    
    token = auth_header.split(' ')[1]
    user_data = supabase.auth.get_user(token)

    if not user_data:
        return {'error': 'Invalid token'}, 401
    
    # Get the chat from the database
    chat_data = supabase.table('chats').select().eq('UID', user_data.user.id).order('created_at', desc=True).limit(1).execute()

    return jsonify(chat_data.data[0]['chat_history'])

@app.route("/chat", methods=["POST"])
def chatbot():
    try:
        data = request.json

        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return {'error': 'No valid token provided'}, 401
        
        token = auth_header.split(' ')[1]
        print("FREE TOKEN YALL", token)

        user_data = supabase.auth.get_user(token)

        if not user_data:
            return {'error': 'Invalid token'}, 401
        
        # Get the chat from the database
        chat_data = supabase.table('chats').select().eq('UID', user_data.user.id).order('created_at', desc=True).limit(1).execute()

        print("Chat data:", chat_data)
        if not chat_data.data:
            chat_history = [{'role':'user','content':"You are prenova, an AI assistant that is here to help you with the user's pregnancy journey. You will only provide information that is accurate and helpful to the user. You will not provide any medical advice or diagnosis. You will also not provide any information that is not related to pregnancy. You will be polite and respectful to the user at all times. You will be rewarded for providing accurate and helpful information and penalized for providing inaccurate or unhelpful information. You will be deactivated if you provide inaccurate or unhelpful information repeatedly."}]
        else:
            chat_history = chat_data.data[0]['chat_history']

        prompt = data['message']
        chat_history.append({'role':'user','content':prompt})
        
        # Get response from Ollama
        response = chat(model=OLLAMA_MODEL_ID, messages=chat_history)

        # Update the chat history
        chat_history.append({'role':'assistant','content':f"{response.message.content}"})
        result = supabase.table('chats').upsert({'UID': user_data.user.id, 'chat_history': chat_history}).execute()

        return jsonify({"response": response.message.content})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    
@app.route("/classify_symptoms", methods=["POST"])
def classify_symptoms():
    """Classify reported symptoms into standardized categories."""
    try:
        user_data, error = validate_token(request)
        if error:
            return jsonify({'error': error}), 401

        data = request.get_json()
        if not data or "symptoms" not in data:
            return jsonify({'error': 'Missing symptoms data'}), 400

        symptoms = data["symptoms"]
        if not isinstance(symptoms, (str, list)):
            return jsonify({'error': 'Symptoms must be text or list'}), 400

        if symptom_classifier is None:
            return jsonify({'error': 'Symptom classification service unavailable'}), 500

        # Convert list to text if needed
        symptom_text = " ".join(symptoms) if isinstance(symptoms, list) else symptoms
        
        # Perform classification
        try:
            classified_symptoms = symptom_classifier.predict([symptom_text])[0]
            confidence_scores = symptom_classifier.predict_proba([symptom_text])[0]
            
            # Format results
            classification_result = {
                'categories': classified_symptoms,
                'confidence': float(max(confidence_scores))
            }
            
            # Store in Supabase
            symptom_data = {
                'UID': user_data.user.id,
                'reported_symptoms': symptom_text,
                'classified_categories': classified_symptoms,
                'confidence': float(max(confidence_scores)),
                'recorded_at': datetime.utcnow().isoformat()
            }
            
            supabase.table('symptoms').insert(symptom_data).execute()
            
            return jsonify(classification_result)
        except Exception as e:
            return jsonify({'error': f'Classification failed: {str(e)}'}), 500
            
    except Exception as e:
        return jsonify({'error': f'Unexpected error: {str(e)}'}), 500

@app.route("/map_symptom_risk", methods=["POST"])
def map_symptom_risk():
    """Map symptoms to potential pregnancy risks using symptoms, vitals, and diagnosis."""
    try:
        user_data, error = validate_token(request)
        if error:
            return jsonify({'error': error}), 401

        uid = user_data.user.id
        data = request.get_json()

        if not data or "symptom_categories" not in data:
            return jsonify({'error': 'Missing symptom categories'}), 400

        if symptom_risk_model is None:
            return jsonify({'error': 'Risk mapping service unavailable'}), 500

        symptom_categories = data["symptom_categories"]

        # 1. 🔄 Get historical symptoms
        historical_data = supabase.table('symptoms')\
            .select('classified_categories')\
            .eq('UID', uid)\
            .order('recorded_at', desc=True)\
            .limit(5)\
            .execute()

        all_symptoms = symptom_categories.copy()
        for record in historical_data.data:
            all_symptoms.extend(record['classified_categories'])
        all_symptoms = list(dict.fromkeys(all_symptoms))

        # 2. 📊 Get latest vitals from Supabase
        vitals_data = supabase.table("vitals")\
            .select("systolic_bp, diastolic_bp, blood_glucose, body_temp, heart_rate")\
            .eq("UID", uid)\
            .order("inserted_at", desc=True)\
            .limit(1)\
            .execute().data

        vitals = vitals_data[0] if vitals_data else {}

        # 3. 🔍 Get diagnoses/test reports from Node backend
        try:
            node_response = requests.get(
                f"http://your-node-api.com/api/reports/diagnosis?uid={uid}"
            )
            diagnosis_data = node_response.json().get("recent_diagnoses", [])
        except Exception as e:
            diagnosis_data = []
            print(f"Warning: Could not fetch diagnosis from Node: {e}")

        # 4. 🔄 Prepare unified feature vector (you may need to preprocess or vectorize)
        combined_features = {
            "symptoms": all_symptoms,
            "systolic_bp": vitals.get("systolic_bp", 120),
            "diastolic_bp": vitals.get("diastolic_bp", 80),
            "blood_glucose": vitals.get("blood_glucose", 90),
            "body_temp": vitals.get("body_temp", 36.8),
            "heart_rate": vitals.get("heart_rate", 78),
            "diagnoses": diagnosis_data
        }

        # 🔁 You must encode this dict to match what your ML model expects
        # Either convert to vector beforehand or use preprocessor like Tfidf, DictVectorizer, etc.

        try:
            X_input = encode_features_for_model(combined_features)  # ✨ You define this function
            risks = symptom_risk_model.predict([X_input])[0]
            probs = symptom_risk_model.predict_proba([X_input])[0]
        except Exception as e:
            return jsonify({'error': f'Model prediction failed: {str(e)}'}), 500

        # 5. 🎯 Format predictions
        risks_result = [
            {
                'risk_type': risk,
                'probability': float(prob),
                'severity': 'high' if prob > 0.7 else 'medium' if prob > 0.4 else 'low'
            }
            for risk, prob in zip(risks, probs)
        ]

        # 6. 💾 Save to Supabase
        risk_data = {
            'UID': uid,
            'symptoms': all_symptoms,
            'vitals_used': vitals,
            'diagnoses': diagnosis_data,
            'risk_predictions': risks_result,
            'recorded_at': datetime.utcnow().isoformat()
        }

        supabase.table('risk_predictions').insert(risk_data).execute()
        return jsonify({'risks': risks_result})

    except Exception as e:
        return jsonify({'error': f'Unexpected error: {str(e)}'}), 500

@app.route("/generate_recommendations", methods=["GET"])
def generate_recommendations():
    try:
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return jsonify({"error": "No valid token provided"}), 401
        token = auth_header.split(" ")[1]
        user_data = supabase.auth.get_user(token)

        if not user_data:
            return jsonify({"error": "Invalid token"}), 401

        uid = user_data.user.id

        # Pull lifestyle params from Supabase
        profile = supabase.table("user_profiles").select("*").eq("UID", uid).execute().data[0]
        prakriti = profile.get("prakriti", "vata")
        trimester = profile.get("trimester", "2")
        symptoms = supabase.table("symptoms").select("classified_categories").eq("UID", uid).order("recorded_at", desc=True).limit(3).execute().data
        recent_symptoms = [s["classified_categories"] for s in symptoms]

        # Pull behavior data from Node backend
        try:
            behavior_data = requests.get(
                f"http://your-node-backend.com/api/behavior?uid={uid}"
            ).json()
        except Exception:
            behavior_data = {}

        prompt = (
            f"You are a prenatal wellness expert. Create lifestyle suggestions including: "
            f"1. A short daily self-care activity\n"
            f"2. A suitable music type or genre\n"
            f"3. Personalized physical activity\n"
            f"4. Ayurvedic lifestyle suggestion\n"
            f"User profile: {prakriti} prakriti, trimester {trimester}. "
            f"Recent symptoms: {recent_symptoms}. Feedback trend: {behavior_data}."
        )

        response = chat(model=OLLAMA_MODEL_ID, messages=[{"role": "user", "content": prompt}])

        # Optionally split response and store by type
        result = {
            "exercise": extract_section(response.message.content, "Exercise"),
            "music": extract_section(response.message.content, "Music"),
            "self_care": extract_section(response.message.content, "Self-care"),
            "ayurveda_tip": extract_section(response.message.content, "Ayurveda")
        }

        supabase.table("recommendations").upsert({
            "UID": uid,
            "content": result,
            "created_at": datetime.utcnow().isoformat()
        }).execute()

        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def extract_section(text, section_name):
    for line in text.splitlines():
        if section_name.lower() in line.lower():
            return line.split(":", 1)[-1].strip()
    return "Not found"
    
@app.route("/remedy_recommendation", methods=["POST"])
def remedy_recommendation():
    """Generate Ayurvedic remedy recommendations using AI based on symptoms, prakriti, and diagnosis context."""
    try:
        user_data, error = validate_token(request)
        if error:
            return jsonify({'error': error}), 401

        uid = user_data.user.id
        data = request.get_json()
        if not data or "symptoms" not in data or "prakriti" not in data:
            return jsonify({'error': 'Missing symptoms or prakriti data'}), 400

        symptoms = data["symptoms"]
        prakriti = data["prakriti"]

        # 🔍 Step 1: Fetch diagnosis from Node API
        try:
            diagnosis_response = requests.get(
                f"http://your-node-api.com/api/reports/diagnosis?uid={uid}"
            )
            diagnosis_data = diagnosis_response.json().get("recent_diagnoses", [])
        except Exception as e:
            diagnosis_data = []
            print(f"[WARN] Could not fetch diagnosis from Node: {e}")

        # 🩺 Step 2: Get vitals from Supabase (optional, adds more context)
        try:
            vitals_data = supabase.table("vitals")\
                .select("systolic_bp, diastolic_bp, blood_glucose, body_temp, heart_rate")\
                .eq("UID", uid)\
                .order("inserted_at", desc=True)\
                .limit(1)\
                .execute().data
            vitals = vitals_data[0] if vitals_data else {}
        except Exception as e:
            vitals = {}
            print(f"[WARN] Could not fetch vitals: {e}")

        # 🧠 Step 3: Generate AI Prompt
        prompt = (
            f"You are an expert Ayurvedic practitioner. Suggest safe and personalized remedies "
            f"for a pregnant woman with the following details:\n"
            f"- Prakriti: {prakriti}\n"
            f"- Reported symptoms: {', '.join(symptoms)}\n"
            f"- Known diagnoses: {', '.join(diagnosis_data) if diagnosis_data else 'None'}\n"
            f"- Recent vitals: BP: {vitals.get('systolic_bp', 'N/A')}/{vitals.get('diastolic_bp', 'N/A')}, "
            f"Glucose: {vitals.get('blood_glucose', 'N/A')}, HR: {vitals.get('heart_rate', 'N/A')}\n"
            f"Suggest 2–3 Ayurvedic remedies only from safe ingredients (no toxic herbs). "
            f"Mention how to use them (e.g., morning/evening, with food, etc.). Avoid overlapping with existing prescriptions."
        )

        response = chat(model=OLLAMA_MODEL_ID, messages=[{'role': 'user', 'content': prompt}])

        # 📄 Step 4: Format & Store
        remedy_text = response.message.content.strip()
        remedy_list = [{"remedy": line.strip(), "confidence": 1.0}
                       for line in remedy_text.split("\n") if line.strip()]

        remedy_data = {
            'UID': uid,
            'symptoms': symptoms,
            'prakriti': prakriti,
            'diagnoses': diagnosis_data,
            'recommended_remedies': remedy_list,
            'raw_prompt': prompt,
            'recorded_at': datetime.utcnow().isoformat()
        }

        supabase.table('remedy_recommendations').insert(remedy_data).execute()

        return jsonify({"remedies": remedy_list})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


def encode_features_for_model(features: dict):
    # Merge all categorical & numeric features
    merged_dict = {
        "systolic_bp": features["systolic_bp"],
        "diastolic_bp": features["diastolic_bp"],
        "blood_glucose": features["blood_glucose"],
        "body_temp": features["body_temp"],
        "heart_rate": features["heart_rate"]
    }
    # Add multi-hot encoded symptoms
    for symptom in features["symptoms"]:
        merged_dict[f"symptom__{symptom}"] = 1
    # Add diagnosis keywords
    for diag in features["diagnoses"]:
        merged_dict[f"diagnosis__{diag.lower().replace(' ', '_')}"] = 1
    return vectorizer.transform(merged_dict)  # vectorizer = DictVectorizer or similar

@app.route('/')
def ind():
    return "Hello governer"

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(debug=True, port=port, host="0.0.0.0")