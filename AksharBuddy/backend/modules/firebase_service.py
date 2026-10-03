import firebase_admin
from firebase_admin import credentials, auth, firestore
import os

# Initialize Firebase only if credentials file exists
firebase_initialized = False
db = None

try:
    if os.path.exists("firebase_key.json"):
        cred = credentials.Certificate("firebase_key.json")
        firebase_admin.initialize_app(cred)
        db = firestore.client()
        firebase_initialized = True
        print("Firebase initialized successfully")
    else:
        print("firebase_key.json not found - Firebase disabled for this session")
except Exception as e:
    print(f"Firebase initialization failed: {e} - Continuing without Firebase")

def create_user(email, password):
    if not firebase_initialized:
        raise Exception("Firebase not initialized - firebase_key.json missing")
    user = auth.create_user(
        email=email,
        password=password
    )
    return user.uid
    
def verify_token(id_token):
    if not firebase_initialized:
        raise Exception("Firebase not initialized - firebase_key.json missing")
    decoded_token = auth.verify_id_token(id_token)
    return decoded_token