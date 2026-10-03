from flask import Blueprint, request, jsonify
from modules.simplifier import process_text
from modules.ocr import extract_text
from modules.firebase_service import verify_token

import numpy as np
import cv2

pipeline_bp = Blueprint("pipeline", __name__)


def get_user_from_request(request):
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        return None
    try:
        token = auth_header.split(" ")[1]
        decoded_user = verify_token(token)
        return decoded_user
    except Exception as e:
        print("Auth Error:", e)
        return None


@pipeline_bp.route("/process/ocr-format", methods=["POST"])
def ocr_and_format():
    """
    Protected pipeline: upload an image → OCR → AI simplification in one call.
    Requires a valid Firebase Bearer token.
    ---
    tags:
      - Pipeline
    consumes:
      - multipart/form-data
    parameters:
      - in: header
        name: Authorization
        type: string
        required: true
        description: 'Firebase Bearer token — format: Bearer <id_token>'
        example: 'Bearer eyJhbGciOiJSUzI1NiIsImtpZCI6Ij...'
      - in: formData
        name: image
        type: file
        required: true
        description: Image file to process (PNG, JPG, JPEG)
      - in: formData
        name: language
        type: string
        enum: [en, hi, mr]
        default: en
        description: OCR and simplification language
    responses:
      200:
        description: Pipeline completed successfully
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            user_id:
              type: string
              example: abc123uid
            original_text:
              type: string
              example: Raw OCR extracted text from image
            formatted_text:
              type: string
              example: Simple version of the text.
      401:
        description: Missing or invalid token
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: false
            error:
              type: string
              example: Unauthorized - Invalid or missing token
      400:
        description: No image or no text detected
      500:
        description: Internal processing error
    """
    user = get_user_from_request(request)

    if not user:
        return jsonify({"success": False, "error": "Unauthorized - Invalid or missing token"}), 401

    try:
        language = request.form.get("language", "en")

        if "image" not in request.files:
            return jsonify({"success": False, "error": "No image provided"}), 400

        image_file = request.files["image"]
        image_bytes = image_file.read()

        if not image_bytes:
            return jsonify({"success": False, "error": "Empty image file"}), 400

        np_array = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(np_array, cv2.IMREAD_COLOR)

        if image is None:
            return jsonify({"success": False, "error": "Invalid image format"}), 400

        extracted_text = extract_text(cv2.cvtColor(image, cv2.COLOR_BGR2RGB), language)

        if not extracted_text:
            return jsonify({"success": False, "error": "No text detected"}), 400

        formatted_text = process_text(extracted_text, language)

        return jsonify({
            "success": True,
            "user_id": user.get("uid"),
            "original_text": extracted_text,
            "formatted_text": formatted_text
        })

    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500
