"""
Simplify Text Routes — POST /api/simplify-text

Takes already-extracted text and simplifies it using the local IndicBART model.
This is a SEPARATE, OPTIONAL step that only runs when the user explicitly
requests simplification (e.g. by pressing a "Simplify Text" button).

This endpoint does NOT do OCR or document extraction.
"""

from flask import Blueprint, request, jsonify
from modules.simplifier import process_text as local_simplify, process_structured_content
from input_processing.structure_analyzer import render_structure

simplify_text_bp = Blueprint("simplify_text", __name__)


@simplify_text_bp.route("/api/simplify-text", methods=["POST"])
def simplify_text():
    """
    Simplify text using the local model AI. Only call this when the user explicitly requests it.
    ---
    tags:
      - Dyslexia Formatter
    consumes:
      - application/json
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - text
          properties:
            text:
              type: string
              description: The extracted text to simplify
              example: The mitochondria is the powerhouse of the cell and produces ATP through cellular respiration.
            language:
              type: string
              enum: [en, hi, mr]
              default: en
              description: Language of the text (en, hi, or mr — the local model will respond in the same language)
            structured_content:
              type: object
              description: Optional document layout model; returned with tables and positions preserved
    responses:
      200:
        description: Text simplified successfully
        schema:
          type: object
          properties:
            status:
              type: string
              example: success
            language:
              type: string
              example: en
            originalText:
              type: string
              example: The mitochondria is the powerhouse of the cell.
            structured_content:
              type: object
              description: Present when a structured_content document was supplied
            simplifiedText:
              type: string
              example: The mitochondria gives energy to the cell.
      400:
        description: Missing or empty text field
        schema:
          type: object
          properties:
            status:
              type: string
              example: error
            error:
              type: string
              example: 'Missing required field: text'
      503:
        description: Local model unavailable
    """
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify(status="error", error="Send a JSON object containing text."), 400

    text = data.get("text", "")
    if not isinstance(text, str):
        return jsonify(status="error", error="Text must be a string."), 400
    text = text.strip()
    language = data.get("language", "en")

    if not text:
        return jsonify({
            "status": "error",
            "error": "Missing required field: text",
        }), 400

    if language not in ("en", "hi", "mr"):
        return jsonify(status="error", error="Choose English, Hindi, or Marathi."), 400

    structure = data.get("structured_content")
    if structure is not None:
        if (not isinstance(structure, dict) or structure.get("type") != "document"
                or not isinstance(structure.get("blocks"), list)
                or any(not isinstance(block, dict) for block in structure["blocks"])):
            return jsonify(status="error", error="Invalid document structure."), 400
        try:
            render_structure(structure)
        except (TypeError, ValueError, KeyError, AttributeError):
            return jsonify(status="error", error="Invalid document structure."), 400

    try:
        if structure is None:
            simplified = local_simplify(text, language)
        else:
            structure = process_structured_content(structure, language)
            simplified = render_structure(structure)
    except ValueError as exc:
        return jsonify(status='error', error=str(exc)), 422
    except Exception:
        return jsonify({
            "status": "error",
            "error": "Simplification is unavailable. Please try again later.",
        }), 503

    return jsonify({
        "status":         "success",
        "provider": "local-indicbart",
        "changed": " ".join(text.split()) != " ".join(simplified.split()),
        "notice": "Model output needs review. Unchanged text is not evidence of successful simplification.",
        "language":       language,
        "originalText":   text,
        "simplifiedText": simplified,
        **({"structured_content": structure} if structure is not None else {}),
    }), 200
