from flask import Blueprint, request, jsonify
from modules.firebase_service import create_user, verify_token

auth_bp = Blueprint("auth", __name__)


@auth_bp.route("/register", methods=["POST"])
def register():
    """
    Register a new user via Firebase Authentication.
    ---
    tags:
      - Auth
    consumes:
      - application/json
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - email
            - password
          properties:
            email:
              type: string
              format: email
              example: student@aksharally.com
            password:
              type: string
              format: password
              example: SecurePass123
    responses:
      200:
        description: User registered successfully
        schema:
          type: object
          properties:
            message:
              type: string
              example: User registered successfully
            uid:
              type: string
              example: abc123uid
      400:
        description: Missing fields or Firebase error
        schema:
          type: object
          properties:
            error:
              type: string
              example: Email and password required
    """
    data = request.get_json()
    email = data.get("email")
    password = data.get("password")

    if not email or not password:
        return jsonify({"error": "Email and password required"}), 400

    try:
        uid = create_user(email, password)
        return jsonify({"message": "User registered successfully", "uid": uid})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@auth_bp.route("/verify", methods=["POST"])
def verify():
    """
    Verify a Firebase ID token.
    ---
    tags:
      - Auth
    consumes:
      - application/json
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - id_token
          properties:
            id_token:
              type: string
              description: Firebase ID token obtained after login
              example: eyJhbGciOiJSUzI1NiIsImtpZCI6Ij...
    responses:
      200:
        description: Token is valid
        schema:
          type: object
          properties:
            message:
              type: string
              example: Token valid
            uid:
              type: string
              example: abc123uid
      401:
        description: Invalid or expired token
        schema:
          type: object
          properties:
            error:
              type: string
              example: Invalid token
    """
    data = request.get_json()
    token = data.get("id_token")

    if not token:
        return jsonify({"error": "Token required"}), 400

    try:
        decoded = verify_token(token)
        return jsonify({"message": "Token valid", "uid": decoded["uid"]})
    except Exception as e:
        return jsonify({"error": "Invalid token"}), 401
