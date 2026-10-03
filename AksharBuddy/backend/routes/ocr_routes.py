from flask import Blueprint, request, jsonify
from modules.ocr import extract_text

ocr_bp = Blueprint("ocr", __name__)


@ocr_bp.route("/process/ocr", methods=["POST"])
def process_ocr():
    """
    Extract text from an uploaded image using OCR.
    ---
    tags:
      - OCR
    consumes:
      - multipart/form-data
    parameters:
      - in: formData
        name: image
        type: file
        required: true
        description: Image file to extract text from (PNG, JPG, JPEG)
      - in: formData
        name: language
        type: string
        enum: [en, hi]
        default: en
        description: OCR language
    responses:
      200:
        description: Text extracted successfully
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            extracted_text:
              type: string
              example: Sample extracted text from image
      400:
        description: Validation error
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: false
            error:
              type: string
              example: No image file provided
      500:
        description: OCR processing error
    """
    if "image" not in request.files:
        return jsonify({"success": False, "error": "No image file provided"}), 400

    image = request.files["image"]
    language = request.form.get("language", "en")

    if not image.filename.lower().endswith((".png", ".jpg", ".jpeg")):
        return jsonify({"success": False, "error": "Invalid file type. Only PNG, JPG, JPEG allowed."}), 400

    try:
        extracted_text = extract_text(image, language)
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

    return jsonify({"success": True, "extracted_text": extracted_text})
