from flask import Flask, request, jsonify
import joblib
import numpy as np
import pandas as pd
import os
import requests
import jwt
from dotenv import load_dotenv
load_dotenv()
from flask_cors import CORS
from datetime import datetime
from typing import Dict, List, Optional, Union
from sklearn.feature_extraction import DictVectorizer
from flask_restx import Api, Resource, fields, Namespace
from supabase import create_client, Client
import logging
from ml_models import SymptomClassifier, SymptomRiskModel, RemedyRecommendationModel
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Initialize Flask-RestX API with documentation settings
api = Api(
    app,
    version='1.0',
    title='AyurJanani Prenatal Care API',
    description='''Comprehensive API for prenatal health monitoring and personalized care recommendations.
    
Features:
- Maternal health monitoring and risk assessment
- Fetal health monitoring with CTG analysis
- Personalized diet recommendations
- AI-powered chat assistance
- Ayurvedic health insights and recommendations
    
All endpoints require authentication. Use the Bearer token received after login.''',
    doc='/api-docs',
    authorizations={
        'Bearer': {
            'type': 'apiKey',
            'in': 'header',
            'name': 'Authorization',
            'description': '''JWT token for authentication.
            
Format: Bearer <token>
Example: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'''
        }
    },
    security='Bearer'
)

# Create namespaces for different API sections with detailed descriptions
auth_ns = Namespace('auth', 
    description='Authentication operations for user login and registration'
)
maternal_ns = Namespace('maternal',
    description='''Maternal health monitoring endpoints.
    Tracks vital signs, symptoms, and predicts potential health risks.'''
)
fetal_ns = Namespace('fetal',
    description='''Fetal health monitoring and CTG analysis.
    Processes cardiotocography data and provides health insights.'''
)
diet_ns = Namespace('diet',
    description='''Personalized diet and nutrition recommendations.
    Generates trimester-specific meal plans considering health conditions and preferences.'''
)
chat_ns = Namespace('chat',
    description='''AI-powered chat assistance for pregnancy-related queries.
    Maintains conversation history and provides contextual responses.'''
)
ayurveda_ns = Namespace('ayurveda',
    description='''Ayurvedic health recommendations and risk assessment.
    Classifies symptoms, maps health risks, and suggests natural remedies.'''
)
generate_recommendations = Namespace('recommendations',
    description='''Personalized lifestyle recommendations.
    Generates daily activities, music, exercises, and wellness tips based on health data.'''
)

# Add namespaces to API
api.add_namespace(auth_ns)
api.add_namespace(maternal_ns)
api.add_namespace(fetal_ns)
api.add_namespace(diet_ns)
api.add_namespace(chat_ns)
api.add_namespace(ayurveda_ns)
api.add_namespace(generate_recommendations)

# Shared models across namespaces
auth_header = api.model('AuthHeader', {
    'Authorization': fields.String(
        required=True,
        description='Bearer token for authentication',
        example='Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...')
})

error_response = api.model('ErrorResponse', {
    'error': fields.String(
        description='Detailed error message',
        example='Invalid token provided')
})

# Maternal namespace models
maternal_input = maternal_ns.model('MaternalInput', {
    'systolic_bp': fields.Integer(
        required=True,
        description='Systolic blood pressure in mmHg',
        example=120,
        min=70,
        max=200
    ),
    'diastolic_bp': fields.Integer(
        required=True,
        description='Diastolic blood pressure in mmHg',
        example=80,
        min=40,
        max=130
    ),
    'blood_glucose': fields.Float(
        required=True,
        description='Blood glucose level in mg/dL',
        example=95.5,
        min=30,
        max=300
    ),
    'body_temp': fields.Float(
        required=True,
        description='Body temperature in °C',
        example=37.2,
        min=35,
        max=42
    ),
    'heart_rate': fields.Integer(
        required=True,
        description='Heart rate in beats per minute',
        example=75,
        min=40,
        max=200
    )
})

maternal_response = maternal_ns.model('MaternalResponse', {
    'prediction': fields.String(description='Predicted risk level (Normal/Suspect/Pathological)'),
    'status': fields.String(description='Detailed status description')
})

# Fetal namespace models
fetal_input = fetal_ns.model('FetalInput', {
    'features': fields.List(fields.Float, required=True, description='List of CTG features, exactly 15 values required')
})

fetal_response = fetal_ns.model('FetalResponse', {
    'prediction': fields.String(description='Predicted fetal health status'),
    'status': fields.String(description='Detailed status description')
})

# Diet namespace models
diet_input = diet_ns.model('DietInput', {
    'trimester': fields.String(
        required=True,
        description='Current pregnancy trimester',
        example='second',
        enum=['first', 'second', 'third']
    ),
    'weight': fields.Float(
        required=True,
        description='Current weight in kilograms',
        example=65.5,
        min=35,
        max=200
    ),
    'health_conditions': fields.String(
        required=True,
        description='Current health conditions or symptoms',
        example='mild morning sickness, slight fatigue'
    ),
    'dietary_preference': fields.String(
        required=True,
        description='Dietary preferences or restrictions',
        example='vegetarian, lactose intolerant'
    )
})

diet_response = diet_ns.model('DietResponse', {
    'diet_plan': fields.String(
        description='Generated personalized diet plan with meal suggestions',
        example=''':
## Morning
- Oatmeal with mixed berries and almond milk
- Fresh orange juice
- Greek yogurt with honey

## Lunch
- Quinoa and chickpea bowl
- Steamed vegetables
- Mixed green salad

## Snacks
- Apple slices with peanut butter
- Mixed nuts and dried fruits

## Dinner
- Grilled tofu with herbs
- Brown rice
- Sautéed spinach
''')
})

# Chat namespace models
chat_input = chat_ns.model('ChatInput', {
    'message': fields.String(
        required=True,
        description='User message to the AI assistant',
        example='What foods are good for morning sickness?'
    )
})

chat_response = chat_ns.model('ChatResponse', {
    'response': fields.String(
        description='AI assistant response',
        example='For morning sickness, try eating small, frequent meals and consider these foods: \n- Ginger tea or candies\n- Plain crackers\n- Bananas\n- Toast with honey\n- Cold foods like yogurt\nAvoid spicy or greasy foods, and stay hydrated.'
    )
})

# Ayurvedic namespace models
symptom_input = ayurveda_ns.model('SymptomInput', {
    'symptoms': fields.Raw(
        required=True,
        description='Symptoms as text or list',
        example=['mild headache', 'lower back pain', 'fatigue']
    )
})

symptom_response = ayurveda_ns.model('SymptomResponse', {
    'categories': fields.List(
        fields.String,
        description='List of classified symptom categories',
        example=['digestive', 'musculoskeletal', 'fatigue']
    ),
    'confidence': fields.Float(
        description='Confidence score for the classification',
        example=0.92,
        min=0,
        max=1
    )
})

symptom_risk_input = ayurveda_ns.model('SymptomRiskInput', {
    'symptom_categories': fields.List(
        fields.String,
        required=True,
        description='List of standardized symptom categories',
        example=['digestive', 'musculoskeletal', 'fatigue']
    )
})

risk_response = ayurveda_ns.model('RiskResponse', {
    'risks': fields.List(
        fields.Nested(api.model('Risk', {
            'risk_type': fields.String(
                description='Type of identified risk',
                example='gestational_diabetes'
            ),
            'probability': fields.Float(
                description='Probability of the risk (0-1)',
                example=0.65,
                min=0,
                max=1
            ),
            'severity': fields.String(
                description='Risk severity level',
                example='medium',
                enum=['low', 'medium', 'high']
            )
        }))
    )
})

node_auth = ayurveda_ns.model('NodeAuth', {
    'Node-Token': fields.String(
        required=True,
        description='Authentication token for Node backend services',
        example='nt_k1abc123xyz..'
    )
})

remedy_input = ayurveda_ns.model('RemedyInput', {
    'symptoms': fields.List(
        fields.String,
        required=True,
        description='List of current symptoms',
        example=['morning sickness', 'fatigue']
    ),
    'prakriti': fields.String(
        required=True,
        description='Ayurvedic body type (Prakriti)',
        example='Pitta-Vata',
        enum=['Vata', 'Pitta', 'Kapha', 'Vata-Pitta', 'Pitta-Kapha', 'Vata-Kapha', 'Tridoshic']
    )
})

remedy_response = ayurveda_ns.model('RemedyResponse', {
    'remedies': fields.List(
        fields.Nested(api.model('Remedy', {
            'remedy': fields.String(
                description='Recommended Ayurvedic remedy with usage instructions',
                example='Ginger tea with honey - Take 1 cup in the morning before breakfast'
            ),
            'confidence': fields.Float(
                description='Confidence score for the recommendation',
                example=0.85,
                min=0,
                max=1
            )
        }))
    )
})

# Response Models
prediction_response = api.model('PredictionResponse', {
    'prediction': fields.String(description='Predicted risk level'),
    'status': fields.String(description='Detailed status description')
})

error_response = api.model('ErrorResponse', {
    'error': fields.String(description='Error message')
})

recommendation_response = api.model('RecommendationResponse', {
    'self_care': fields.String(
        description='Recommended daily self-care activity',
        example='10-minute morning meditation with deep breathing exercises'
    ),
    'music': fields.String(
        description='Recommended music type or genre',
        example='Soft classical music with nature sounds'
    ),
    'exercise': fields.String(
        description='Recommended pregnancy-safe exercise',
        example='Gentle prenatal yoga focusing on hip and back stretches'
    ),
    'ayurveda_tip': fields.String(
        description='Daily Ayurvedic wellness tip',
        example='Start your day with warm lemon water to aid digestion'
    )
})

# Environment variables and other configurations
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")
SUPABASE_JWT_SECRET = os.environ["SUPABASE_JWT_SECRET"]
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
    os.path.join(MODEL_PATH, 'ayurvedic', 'symptom_classifier_model.pkl'),
    'Symptom classification may be limited'
)

symptom_risk_model = load_model_safely(
    os.path.join(MODEL_PATH, 'ayurvedic', 'symptom_risk_model.pkl'),
    'Risk prediction may be limited'
)

remedy_model = load_model_safely(
    os.path.join(MODEL_PATH, 'ayurvedic', 'remedy_model.pkl'),
    'Remedy suggestions may be limited'
)

# Custom chat function to replace ollama-python client
def chat(model, messages):
    """
    Send a chat request to Groq API (OpenAI-compatible) using the requests library
    """
    import os
    import requests
    class DotDict(dict):
        """Dot notation access to dictionary attributes"""
        def __getattr__(self, name):
            try:
                return self[name]
            except KeyError:
                raise AttributeError(name)
        __setattr__ = dict.__setitem__
        __delattr__ = dict.__delitem__

    GROQ_API_KEY = os.environ.get("GROQ_API_KEY")
    if not GROQ_API_KEY:
        raise RuntimeError("GROQ_API_KEY environment variable not set.")
    GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {GROQ_API_KEY}",
        "Content-Type": "application/json"
    }
    payload = {
        "model": model,
        "messages": messages
    }
    try:
        response = requests.post(GROQ_API_URL, headers=headers, json=payload)
        response.raise_for_status()
        result = response.json()
        # Emulate Ollama's response structure for compatibility
        message_content = result["choices"][0]["message"]["content"]
        result_obj = DotDict({"message": DotDict({"content": message_content})})
        return result_obj
    except Exception as e:
        print(f"Error in chat function (Groq): {str(e)}")
        raise

# Utility function for token validation
def validate_token(request) -> tuple[Optional[dict], Optional[str]]:
    auth_header = request.headers.get('Authorization', '')
    if not auth_header.startswith('Bearer '):
        return None, 'No valid token provided'

    token = auth_header.split(' ')[1]
    try:
        # verify signature and audience
        claims = jwt.decode(
            token,
            SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            audience="authenticated"
        )
        return claims, None

    except jwt.ExpiredSignatureError:
        return None, 'Token expired'
    except jwt.InvalidAudienceError:
        return None, 'Token audience mismatch'
    except jwt.InvalidTokenError:
        return None, 'Invalid token'

@maternal_ns.route('/predict')
class MaternalPrediction(Resource):
    @maternal_ns.doc('predict_maternal',
        description='''Analyze maternal health metrics and predict potential risks.
        Processes vital signs and generates risk assessment based on machine learning models.''')
    @maternal_ns.expect(auth_header, maternal_input)
    @maternal_ns.response(200, 'Success', prediction_response)
    @maternal_ns.response(401, 'Unauthorized - Invalid or missing token', error_response)
    @maternal_ns.response(400, 'Bad Request - Invalid input data', error_response)
    @maternal_ns.response(500, 'Server Error - Prediction service unavailable', error_response)
    def post(self):
        print("[MaternalPrediction] Endpoint hit", flush=True)
        logger.info("[MaternalPrediction] Endpoint hit")
        '''Predict maternal health risks based on vital signs'''
        try:
            logger.info(f"Request headers: {dict(request.headers)}")
            logger.info(f"Request body: {request.get_json()}")
            print("Authentication header: ", request.headers.get('Authorization'))
            claims, error = validate_token(request)
            if error:
                logger.warning(f"Token validation error: {error}")
                return {'error': error}, 401

            user_id = claims.get('sub') if claims else None
            if not user_id:
                logger.warning("Token missing subject (sub)")
                return {'error': 'Token missing subject'}, 401

            logger.info(f"Authenticated request by user_id: {user_id}")
            data = request.get_json()
            logger.info(f"Parsed request data: {data}")


            FEATURE_NAMES = [
                "Age", "SystolicBP", "DiastolicBP",
                "BS", "BodyTemp", "HeartRate"
            ]
            try:
                features = pd.DataFrame([[
                    float(data["age"]),            
                    float(data["systolic_bp"]),  
                    float(data["diastolic_bp"]),   
                    float(data["blood_glucose"]), 
                    float(data["body_temp"]),      
                    float(data["heart_rate"]), 
                ]], columns=FEATURE_NAMES)
            except Exception as e:
                logger.error(f"Error parsing features from request: {e}")
                return {"error": f"Invalid input data: {e}"}, 400

            logger.info(f"Features DataFrame: {features}")

            try:
                scaled_features = maternal_scaler.transform(features)
                logger.info(f"Scaled features: {scaled_features}")
            except Exception as e:
                logger.error(f"Error scaling features: {e}")
                return {"error": f"Feature scaling failed: {e}"}, 500

            try:
                prediction = maternal_model.predict(scaled_features)
                logger.info(f"Model prediction: {prediction}")
            except Exception as e:
                logger.error(f"Error in model prediction: {e}")
                return {"error": f"Prediction failed: {e}"}, 500

            risk_mapping = {0: "Normal", 1: "Suspect", 2: "Pathological"}
            risk_level = risk_mapping.get(int(prediction[0]), "Unknown")
            logger.info(f"Predicted risk level: {risk_level}")

            # Insert into vitals table   
            vital_data = {
                'UID': user_id,
                'systolic_bp': data["systolic_bp"],
                'diastolic_bp': data["diastolic_bp"],
                'blood_glucose': data["blood_glucose"],
                'body_temp': data["body_temp"],
                'heart_rate': data["heart_rate"],
                'prediction': int(prediction[0])
            }
            logger.info(f"Inserting vitals data: {vital_data}")
            try:
                result = supabase.table('vitals').insert(vital_data).execute()
                logger.info(f"Supabase insert result: {result}")
            except Exception as e:
                logger.warning(f"Failed to insert vitals into Supabase: {e}")

            return {"prediction": risk_level}, 200

        except Exception as e:
            logger.error(f"Unhandled error in maternal prediction: {e}", exc_info=True)
            return {"error": str(e)}, 500

@fetal_ns.route('/predict', methods=['POST'])
class FetalPrediction(Resource):
    @fetal_ns.doc('predict_fetal',
        description='''Analyze fetal health parameters from CTG data.
        Processes cardiotocography measurements to assess fetal well-being.''')
    @fetal_ns.expect(auth_header, fetal_input)
    @fetal_ns.response(200, 'Success', prediction_response)
    @fetal_ns.response(401, 'Unauthorized - Invalid or missing token', error_response)
    @fetal_ns.response(400, 'Bad Request - Invalid input data', error_response)
    @fetal_ns.response(500, 'Server Error - Prediction service unavailable', error_response)
    def post(self):
        # 1) Validate token & get claims
        claims, error = validate_token(request)
        if error:
            return {'error': error}, 401

        user_id = claims.get('sub')
        if not user_id:
            return {'error': 'Token missing subject'}, 401
        logger.info(f"Authenticated request by user_id: {user_id}")
        # 2) Parse input JSON
        data = request.get_json()
        if not data or 'features' not in data:
            return {'error': 'Missing required feature data'}, 400

        # 3) Validate & reshape features
        features = np.array(data['features'], dtype=float)
        if features.size != 15:
            return {'error': 'Invalid feature length, expected 15'}, 400
        features = features.reshape(1, -1)

        # 4) Scale
        try:
            scaled = fetal_scaler.transform(features)
        except Exception as e:
            return {'error': f'Feature scaling failed: {e}'}, 500

        # 5) Predict
        try:
            pred = int(fetal_model.predict(scaled)[0])
        except Exception as e:
            return {'error': f'Prediction failed: {e}'}, 500

        # 6) Map status
        status_map = {0: 'Normal', 1: 'Suspect', 2: 'Pathological'}
        status = status_map.get(pred, 'Unknown')

        # 7) Prepare CTG data
        feature_names = [
            'baseline_value','accelerations','fetal_movement','uterine_contractions',
            'light_decelerations','severe_decelerations','prolonged_decelerations',
            'abnormal_short_term_variability','mean_value_of_short_term_variability',
            'percentage_of_time_with_abnormal_long_term_variability',
            'mean_value_of_long_term_variability','histogram_width','histogram_min',
            'histogram_max','histogram_number_of_peaks'
        ]
        feature_dict = {k: float(v) for k, v in zip(feature_names, features.flatten())}

        ctg_data = {
            'UID': user_id,
            **feature_dict,
            'prediction': pred
        }
        logger.info(f"Supabase CTG data: {ctg_data}")
        logger.info(f"Supabase Key: {SUPABASE_KEY}")
        # 8) Store to Supabase
        try:
            supabase.table('ctg').insert(ctg_data).execute()
        except Exception as e:
            logger.warning(f"Failed to store CTG data: {e}")

        # 9) Return response
        return {'prediction': pred, 'status': status}, 200

@diet_ns.route('/plan')
class DietPlan(Resource):
    @diet_ns.doc('get_diet_plan',
        description='''Generate personalized diet recommendations.
        Creates trimester-specific meal plans considering health conditions and dietary preferences.''')
    @diet_ns.expect(auth_header, diet_input)
    @diet_ns.response(200, 'Success', diet_response)
    @diet_ns.response(401, 'Unauthorized - Invalid or missing token', error_response)
    @diet_ns.response(500, 'Server Error - Diet planning service unavailable', error_response)
    def post(self):
        print("[DietPlan] Endpoint hit", flush=True)
        logger.info("[DietPlan] Endpoint hit")
        '''Generate personalized diet plan based on trimester and preferences'''
        try:
            claims, error = validate_token(request)
            if error:
                return {'error': error}, 401
            user_id = claims.get('sub') if claims else None
            if not user_id:
                return {'error': 'Token missing subject'}, 401
            data = request.get_json()
            if not data:
                return {'error': 'Missing input data'}, 400
            prompt = f"You are a professional dietician and nutritionist. You suggest excellent diet plans for pregnant women that look after their well being and growth. You will now suggest a diet plan for a {data['trimester']} trimester pregnant woman weighing about {data['weight']} kg, who is feeling {data['health_conditions']} and has strict dietary preferences as follows: {data['dietary_preference']}. Do not suggest any foods that can cause harm or go against the dietary preferences. Integrate Ayurveda recipies into your recommendation, emphasize its benefits, and let natural choices be a high priority. Be clearer and concise in your response, providing a meal plan for the day with breakfast, lunch, snacks, and dinner. Include portion sizes and any specific Ayurvedic ingredients that would be beneficial for her condition."
            response = chat(model=OLLAMA_MODEL_ID, messages=[{'role':'user','content':prompt}])
            diet_data = {
                'UID': user_id,
                'diet_plan': response.message.content
            }
            return {'diet_plan': response.message.content}, 200
        except Exception as e:
            return {'error': str(e)}, 500
    
@chat_ns.route('/history')
class ChatBot(Resource):
    @chat_ns.doc('get_chat_history',
        description='''Retrieve chat history for the current user.
        Returns all previous conversations with the AI assistant.''')
    @chat_ns.expect(auth_header)
    @chat_ns.response(200, 'Success', chat_response)
    @chat_ns.response(401, 'Unauthorized - Invalid or missing token', error_response)
    @chat_ns.response(500, 'Server Error - Chat history unavailable', error_response)
    def get(self):
        print("[ChatBot GET] Endpoint hit", flush=True)
        logger.info("[ChatBot GET] Endpoint hit")
        '''Get chat history for the current user'''
        try:
            claims, error = validate_token(request)
            if error:
                return {'error': error}, 401
            user_id = claims.get('sub') if claims else None
            if not user_id:
                return {'error': 'Token missing subject'}, 401
            chat_data = supabase.table('chats')\
                .select()\
                .eq('UID', user_id)\
                .order('created_at', desc=True)\
                .limit(1)\
                .execute()
            if not chat_data.data:
                return [], 200
            return chat_data.data[0]['chat_history'], 200
        except Exception as e:
            return {'error': str(e)}, 500

    @chat_ns.doc('send_message',
        description='''Send a message to the AI assistant.
        Maintains conversation context and provides pregnancy-relevant responses.''')
    @chat_ns.expect(auth_header, chat_input)
    @chat_ns.response(200, 'Success', chat_response)
    @chat_ns.response(401, 'Unauthorized - Invalid or missing token', error_response)
    @chat_ns.response(400, 'Bad Request - Invalid message format', error_response)
    @chat_ns.response(500, 'Server Error - Chat service unavailable', error_response)
    def post(self):
        print("[ChatBot POST] Endpoint hit", flush=True)
        logger.info("[ChatBot POST] Endpoint hit")
        '''Send a message to the AI assistant'''
        try:
            claims, error = validate_token(request)
            if error:
                return {'error': error}, 401
            user_id = claims.get('sub') if claims else None
            if not user_id:
                return {'error': 'Token missing subject'}, 401
            data = request.get_json()
            if not data or 'message' not in data:
                return {'error': 'Missing message'}, 400
            chat_data = supabase.table('chats')\
                .select()\
                .eq('UID', user_id)\
                .order('created_at', desc=True)\
                .limit(1)\
                .execute()
            if not chat_data.data:
                chat_history = [{'role':'system','content':"You are AyurJanani, an AI assistant that is here to help you with the user's pregnancy journey and clear any doubts in ayurveda. You will only provide information that is accurate and helpful to the user. You will not provide any medical advice or diagnosis. You will not provide any information that is not related to pregnancy or ayurveda. You will be polite and respectful to the user at all times."}]
            else:
                chat_history = chat_data.data[0]['chat_history']
            prompt = data['message']
            chat_history.append({'role':'user','content':prompt})
            response = chat(model=OLLAMA_MODEL_ID, messages=chat_history)
            chat_history.append({'role':'assistant','content':response.message.content})
            try:
                supabase.table('chats').upsert({
                    'UID': user_id,
                    'chat_history': chat_history
                }).execute()
            except Exception as e:
                logger.warning(f"Failed to store chat history: {str(e)}")
            return {'response': response.message.content}, 200
        except Exception as e:
            return {'error': str(e)}, 500
    
@ayurveda_ns.route('/classify_symptoms')
class SymptomClassification(Resource):
    @ayurveda_ns.doc('classify_symptoms',
        description='''Classify reported symptoms into standardized categories.
        Uses machine learning to map user-reported symptoms to medical categories.''')
    @ayurveda_ns.expect(auth_header, symptom_input)
    @ayurveda_ns.response(200, 'Success', symptom_response)
    @ayurveda_ns.response(401, 'Unauthorized - Invalid or missing token', error_response)
    @ayurveda_ns.response(400, 'Bad Request - Invalid symptoms data', error_response)
    @ayurveda_ns.response(500, 'Server Error - Classification service unavailable', error_response)
    def post(self):
        print("[SymptomClassification] Endpoint hit", flush=True)
        logger.info("[SymptomClassification] Endpoint hit")
        '''Classify reported symptoms into standardized categories'''
        try:
            claims, error = validate_token(request)
            if error:
                return {'error': error}, 401
            user_id = claims.get('sub') if claims else None
            if not user_id:
                return {'error': 'Token missing subject'}, 401
            data = request.get_json()
            if not data or "symptoms" not in data:
                return {'error': 'Missing symptoms data'}, 400
            symptoms = data["symptoms"]
            if not isinstance(symptoms, (str, list)):
                return {'error': 'Symptoms must be text or list'}, 400
            if symptom_classifier is None:
                return {'error': 'Symptom classification service unavailable'}, 500
            symptom_text = " ".join(symptoms) if isinstance(symptoms, list) else symptoms
            logger.info(f"[SymptomClassification] Input symptom_text: {symptom_text}")
            try:
                prediction_raw = symptom_classifier.predict([symptom_text])
                logger.info(f"[SymptomClassification] Raw model prediction: {prediction_raw}")
                classified_symptoms = prediction_raw[0]
                confidence_scores = symptom_classifier.predict_proba([symptom_text])[0]
                logger.info(f"[SymptomClassification] Model confidence scores: {confidence_scores}")
                classification_result = {
                    'categories': classified_symptoms,
                    'confidence': float(max(confidence_scores))
                }
                symptom_data = {
                    'UID': user_id,
                    'reported_symptoms': symptom_text,
                    'classified_categories': classified_symptoms,
                    'confidence': float(max(confidence_scores)),
                    'recorded_at': datetime.utcnow().isoformat()
                }
                try:
                    supabase.table('symptoms').insert(symptom_data).execute()
                except Exception as e:
                    logger.warning(f"Failed to store symptom data: {str(e)}")
                return classification_result, 200
            except Exception as e:
                logger.error(f"[SymptomClassification] Exception: {str(e)}", exc_info=True)
                return {'error': f'Classification failed: {str(e)}'}, 500
        except Exception as e:
            return {'error': f'Unexpected error: {str(e)}'}, 500

@ayurveda_ns.route('/map_symptom_risk')
class SymptomRiskMapping(Resource):
    @ayurveda_ns.doc('map_symptom_risk',
        description='''Map symptoms to potential pregnancy risks.
        Analyzes symptoms, vitals, and diagnosis history to assess health risks.''')
    @ayurveda_ns.expect(auth_header, node_auth, symptom_risk_input)
    @ayurveda_ns.response(200, 'Success', risk_response)
    @ayurveda_ns.response(401, 'Unauthorized - Invalid or missing token', error_response)
    @ayurveda_ns.response(400, 'Bad Request - Invalid symptom categories', error_response)
    @ayurveda_ns.response(500, 'Server Error - Risk mapping service unavailable', error_response)
    def post(self):
        print("[SymptomRiskMapping] Endpoint hit", flush=True)
        logger.info("[SymptomRiskMapping] Endpoint hit")

        try:
        # Validate token
            claims, error = validate_token(request)
            if error:
                return {'error': error}, 401
            user_id = claims.get('sub')
            if not user_id:
                return {'error': 'Token missing subject'}, 401

        # Validate request body
            data = request.get_json()
            if not data or "symptom_categories" not in data:
                return {'error': 'Missing symptom categories'}, 400

            if symptom_risk_model is None:
                return {'error': 'Risk mapping service unavailable'}, 500

            symptoms = list(dict.fromkeys(data["symptom_categories"]))  # Remove duplicates

        # Get most recent vitals (optional fallback values)
            vitals_data = supabase.table("vitals")\
                .select("systolic_bp, diastolic_bp, blood_glucose, body_temp, heart_rate")\
                .eq("UID", user_id)\
                .order("created_at", desc=True)\
                .limit(1)\
                .execute()
            vitals = vitals_data.data[0] if vitals_data.data else {}

        # Prepare input features
            model_features = {
            "symptoms": symptoms,
            "systolic_bp": vitals.get("systolic_bp", 120),
            "diastolic_bp": vitals.get("diastolic_bp", 80),
            "blood_glucose": vitals.get("blood_glucose", 90),
            "body_temp": vitals.get("body_temp", 36.8),
            "heart_rate": vitals.get("heart_rate", 78)
            }

            try:
                X = encode_features_for_model(model_features)
                risks = symptom_risk_model.model.predict(X)[0]
                probs = symptom_risk_model.model.predict_proba(X)[0]
                risk_labels = symptom_risk_model.label_binarizer.classes_

                risks_result = []
                for idx, label in enumerate(risk_labels):
                    prob = float(probs[idx])
                    if label in risks:
                        risks_result.append({
                        'risk_type': label,
                        'probability': round(prob, 4),
                        'severity': 'high' if prob > 0.7 else 'medium' if prob > 0.4 else 'low'
                        })

            # Save the assessment
                risk_data = {
                'UID': user_id,
                'symptoms': symptoms,
                'risks': risks_result,
                'assessed_at': datetime.utcnow().isoformat()
                }
                try:
                    supabase.table('risk_assessments').insert(risk_data).execute()
                except Exception as e:
                    logger.warning(f"Failed to store risk assessment: {str(e)}")

                return {'risks': risks_result}, 200

            except Exception as e:
                logger.warning(f"Risk prediction failed: {str(e)}")
                return {'error': f'Risk prediction failed: {str(e)}'}, 500

        except Exception as e:
            logger.error(f"Unexpected error: {str(e)}")
            return {'error': f'Unexpected error: {str(e)}'}, 500


@generate_recommendations.route('/')
class GenerateRecommendations(Resource):
    @generate_recommendations.doc('generate_recommendations',
        description='''Generate personalized lifestyle recommendations.\nProvides daily activities, music, exercises, and Ayurvedic tips based on health data.''')
    @api.expect(auth_header)
    @api.response(200, 'Success', recommendation_response)
    @api.response(401, 'Unauthorized - Invalid or missing token', error_response)
    @api.response(500, 'Server Error - Recommendation service unavailable', error_response)
    def get(self):
        print("[GenerateRecommendations] Endpoint hit", flush=True)
        logger.info("[GenerateRecommendations] Endpoint hit")
        '''Generate personalized lifestyle recommendations'''
        try:
            claims, error = validate_token(request)
            if error:
                return {'error': error}, 401
            user_id = claims.get('sub') if claims else None
            if not user_id:
                return {'error': 'Token missing subject'}, 401
            symptoms = supabase.table("symptoms")\
                .select("classified_categories")\
                .eq("UID", user_id)\
                .order("recorded_at", desc=True)\
                .limit(3)\
                .execute()
            recent_symptoms = [s["classified_categories"] for s in symptoms.data]
            vitals = supabase.table("vitals")\
                .select("systolic_bp, diastolic_bp, blood_glucose, body_temp, heart_rate")\
                .eq("UID", user_id)\
                .order("created_at", desc=True)\
                .limit(1)\
                .execute()
            vitals_data = vitals.data[0] if vitals.data else {}
            delivery_done = 'delivery_done' in request.args and request.args['delivery_done'].lower() == 'true'
            if delivery_done:
                prompt = (
                    f"You are a postpartum wellness expert. Create lifestyle suggestions including:\n"
                    f"1. A short daily self-care activity to aid postpartum recovery\n"
                    f"2. A suitable music type or genre for emotional well-being\n"
                    f"3. A gentle exercise appropriate for postpartum women\n"
                    f"4. An Ayurvedic tip for healing and lactation\n\n"
                
        f"Context:\n"
        f"Recent symptoms: {', '.join(sum(recent_symptoms, []))}\n"
        f"Vitals: BP {vitals_data.get('systolic_bp', 'N/A')}/{vitals_data.get('diastolic_bp', 'N/A')}, "
        f"Glucose: {vitals_data.get('blood_glucose', 'N/A')}, HR: {vitals_data.get('heart_rate', 'N/A')}\n"
        f"The user has recently given birth. Focus on postpartum care."
    )
            else:
                prompt = (
        f"You are a prenatal wellness expert. Create lifestyle suggestions including:\n"
        f"1. A short daily self-care activity\n"
        f"2. A suitable music type or genre\n"
        f"3. A specific exercise suitable for their condition\n"
        f"4. An Ayurvedic tip\n\n"
        f"Context:\n"
        f"Recent symptoms: {', '.join(sum(recent_symptoms, []))}\n"
        f"Vitals: BP {vitals_data.get('systolic_bp', 'N/A')}/{vitals_data.get('diastolic_bp', 'N/A')}, "
        f"Glucose: {vitals_data.get('blood_glucose', 'N/A')}, HR: {vitals_data.get('heart_rate', 'N/A')}"
    )
            response = chat(model=OLLAMA_MODEL_ID, messages=[{'role': 'user', 'content': prompt}])
            result = {
                "self_care": extract_section(response.message.content, "self-care"),
                "music": extract_section(response.message.content, "music"),
                "exercise": extract_section(response.message.content, "exercise"),
                "ayurveda_tip": extract_section(response.message.content, "Ayurveda")
            }
            return result, 200
        except Exception as e:
            return {'error': str(e)}, 500

def extract_section(text, section_name):
    # Try to extract section by looking for the section name as a heading or in a line
    import re
    # Try heading style: e.g. 'Self-care:', 'Music:', etc.
    pattern = re.compile(rf"{section_name}[:\-]?\s*(.*)", re.IGNORECASE)
    for line in text.splitlines():
        match = pattern.match(line.strip())
        if match:
            value = match.group(1).strip()
            if value:
                return value
    # Try to find a bullet list under the section
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if section_name.lower() in line.lower():
            # Collect subsequent bullet points
            bullets = []
            for l in lines[i+1:]:
                if l.strip().startswith('-') or l.strip().startswith('*'):
                    bullets.append(l.strip('-* ').strip())
                elif l.strip() == '' or l.strip().startswith('#'):
                    continue
                else:
                    break
            if bullets:
                return '\n'.join(bullets)
    return "Not found"
    
@ayurveda_ns.route('/remedy_recommendation')
class RemedyRecommendation(Resource):
    @ayurveda_ns.doc('get_remedy_recommendations',
        description='''Get personalized Ayurvedic remedy recommendations.
        Suggests safe natural remedies based on symptoms, body type, and health history.''')
    @ayurveda_ns.expect(auth_header, node_auth, remedy_input)
    @ayurveda_ns.response(200, 'Success', remedy_response)
    @ayurveda_ns.response(401, 'Unauthorized - Invalid or missing token', error_response)
    @ayurveda_ns.response(400, 'Bad Request - Missing required fields', error_response)
    @ayurveda_ns.response(500, 'Server Error - Recommendation service unavailable', error_response)
    def post(self):
        print("[RemedyRecommendation] Endpoint hit", flush=True)
        logger.info("[RemedyRecommendation] Endpoint hit")
        '''Get personalized Ayurvedic remedy recommendations (let chat decide prakriti)'''
        try:
            claims, error = validate_token(request)
            if error:
                return {'error': error}, 401
            user_id = claims.get('sub') if claims else None
            if not user_id:
                return {'error': 'Token missing subject'}, 401
            data = request.get_json()
            if not data or 'symptoms' not in data:
                return {'error': 'Missing required field: symptoms'}, 400
            symptoms = data["symptoms"]
            try:
                headers = {'Node-Token': data.get('node_token')} if 'node_token' in data else {}
                diagnosis_data = []
                if headers:
                    diagnosis_response = requests.get(
                        f"http://your-node-api.com/api/reports/diagnosis",
                        headers=headers
                    )
                    diagnosis_data = diagnosis_response.json().get("recent_diagnoses", [])
            except Exception as e:
                diagnosis_data = []
                logger.warning(f"Could not fetch diagnosis from Node: {e}")
            try:
                vitals_data = supabase.table("vitals")\
                    .select("systolic_bp, diastolic_bp, blood_glucose, body_temp, heart_rate")\
                    .eq("UID", user_id)\
                    .order("created_at", desc=True)\
                    .limit(1)\
                    .execute()
                vitals = vitals_data.data[0] if vitals_data.data else {}
            except Exception as e:
                vitals = {}
                logger.warning(f"Could not fetch vitals: {e}")
            delivery_done = data.get('delivery_done', False)

            if delivery_done:
                prompt = (
                    f"You are an expert Ayurvedic practitioner. Based on the following details, suggest Ayurvedic postpartum care remedies. "
                    f"Focus on safe, natural ways to help the mother recover physically and mentally. Suggest only safe herbs, dietary practices, or routines. "
                    f"Details:\n"
                    f"- Reported symptoms: {', '.join(symptoms)}\n"
    
        f"- Known diagnoses: {', '.join(diagnosis_data) if diagnosis_data else 'None'}\n"
        f"- Recent vitals: BP: {vitals.get('systolic_bp', 'N/A')}/{vitals.get('diastolic_bp', 'N/A')}, "
        f"Glucose: {vitals.get('blood_glucose', 'N/A')}, HR: {vitals.get('heart_rate', 'N/A')}\n"
        f"Suggest 2–3 remedies suitable for postpartum recovery. Mention usage instructions (e.g., time, method). "
        f"Also mention dietary or routine advice briefly. Avoid anything unsafe for lactating mothers."
                )
            else:
                prompt = (
                    f"You are an expert Ayurvedic practitioner. Based on the following details, first decide the user's prakriti (body type) as one of: Vata, Pitta, Kapha, Vata-Pitta, Pitta-Kapha, Vata-Kapha, or Tridoshic, and then suggest safe and personalized remedies. "
                    f"For a pregnant woman with the following details:\n"
                    f"- Reported symptoms: {', '.join(symptoms)}\n"
                    f"- Known diagnoses: {', '.join(diagnosis_data) if diagnosis_data else 'None'}\n"
                    f"- Recent vitals: BP: {vitals.get('systolic_bp', 'N/A')}/{vitals.get('diastolic_bp', 'N/A')}, "
        f"Glucose: {vitals.get('blood_glucose', 'N/A')}, HR: {vitals.get('heart_rate', 'N/A')}\n"
        f"Suggest 2–3 Ayurvedic remedies only from safe ingredients (no toxic herbs). "
        f"Mention how to use them (e.g., morning/evening, with food, etc.). Avoid overlapping with existing prescriptions. "
        f"First, state the prakriti you have determined, then list the remedies."
            )
            response = chat(model=OLLAMA_MODEL_ID, messages=[{'role': 'user', 'content': prompt}])
            remedy_text = response.message.content.strip()
            # Try to extract prakriti from the first line if present
            lines = remedy_text.split("\n")
            prakriti = None
            if lines and (':' in lines[0] or 'prakriti' in lines[0].lower()):
                prakriti = lines[0].split(":", 1)[-1].strip() if ':' in lines[0] else lines[0].strip()
            # Extract remedies (skip first line if it's prakriti)
            remedy_lines = lines[1:] if prakriti else lines
            remedy_list = [
                {"remedy": line.strip(), "confidence": 1.0}
                for line in remedy_lines
                if line.strip()
            ]
            remedy_data = {
                'UID': user_id,
                'symptoms': symptoms,
                'prakriti': prakriti,
                'diagnoses': diagnosis_data,
                'recommended_remedies': remedy_list,
                'raw_prompt': prompt,
                'recorded_at': datetime.utcnow().isoformat()
            }
            try:
                supabase.table('remedy_recommendations').insert(remedy_data).execute()
            except Exception as e:
                logger.warning(f"Failed to store remedy recommendations: {str(e)}")
            return {'prakriti': prakriti, 'remedies': remedy_list}, 200
        except Exception as e:
            return {'error': str(e)}, 500


def encode_features_for_model(features: dict):
    vector = {
        "systolic_bp": features.get("systolic_bp", 120),
        "diastolic_bp": features.get("diastolic_bp", 80),
        "blood_glucose": features.get("blood_glucose", 90),
        "body_temp": features.get("body_temp", 36.8),
        "heart_rate": features.get("heart_rate", 78)
    }
    for symptom in features.get("symptoms", []):
        vector[f"symptom__{symptom}"] = 1
    return vectorizer.transform([vector])

@api.route('/')
class Index(Resource):
    @api.doc('index')
    def get(self):
        return "Hello governor"

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    
    app.run(debug=False, port=port, host="0.0.0.0")
