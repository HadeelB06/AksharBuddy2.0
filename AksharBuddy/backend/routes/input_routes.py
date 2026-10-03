from flask import Blueprint, request, jsonify
from input_processing.input_router import route_input

input_bp = Blueprint("input", __name__)


@input_bp.route("/api/process-input", methods=["POST"])
def process_input():
    """
    Unified input processing endpoint.
    Accepts typed text, image uploads, camera captures, PDFs, and DOCX files.
    ---
    tags:
      - Input Processing
    consumes:
      - multipart/form-data
      - application/json
    parameters:
      - in: query
        name: language
        type: string
        enum: [en, hi]
        default: en
        description: OCR language — 'en' for English, 'hi' for Hindi (Devanagari)
      - in: formData
        name: text
        type: string
        description: >
          Direct typed text input. Send this field WITHOUT a 'file' field to
          trigger the text processor.
        example: The quick brown fox jumps over the lazy dog
      - in: formData
        name: file
        type: file
        description: >
          File to process. Supported types:
          JPG / JPEG / PNG / WEBP (image or camera capture),
          PDF (text-based or scanned),
          DOCX (Word document).
    responses:
      200:
        description: Text successfully extracted
        schema:
          type: object
          properties:
            status:
              type: string
              example: success
            sourceType:
              type: string
              enum: [text, image, pdf, docx]
              example: image
            extractedText:
              type: string
              example: The quick brown fox jumps over the lazy dog
            characterCount:
              type: integer
              example: 43
            wordCount:
              type: integer
              example: 9
      400:
        description: Validation error or extraction failure
        schema:
          type: object
          properties:
            status:
              type: string
              example: error
            sourceType:
              type: string
              example: unknown
            extractedText:
              type: string
              example: ""
            characterCount:
              type: integer
              example: 0
            wordCount:
              type: integer
              example: 0
            error:
              type: string
              example: No input provided. Send a 'text' field or a 'file' upload.
    """
    language = request.args.get("language") or request.form.get("language", "en")
    result = route_input(request, language)
    http_status = 200 if result.get("status") == "success" else 400
    return jsonify(result), http_status
