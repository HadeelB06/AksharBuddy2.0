from flask import Blueprint, request, jsonify
from modules.simplifier import process_text, process_structured_content
from input_processing.structure_analyzer import render_structure

simplify_bp = Blueprint("simplify", __name__)


@simplify_bp.route("/process/text-format", methods=["POST"])
def process_simplify():
    """
    Simplify text for dyslexia-friendly reading using the local IndicBART model.
    ---
    tags:
      - Simplification
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
              description: The text to simplify
              example: The mitochondria is the powerhouse of the cell and produces ATP through cellular respiration.
            language:
              type: string
              enum: [en, hi, mr]
              default: en
              description: Language of the text
    responses:
      200:
        description: Text simplified successfully
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            original_text:
              type: string
              example: The mitochondria is the powerhouse of the cell.
            formatted_text:
              type: string
              example: Mitochondria makes energy. It powers the cell.
      400:
        description: No text provided
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: false
            error:
              type: string
              example: No text provided
    """
    # Reuse the validated local-model endpoint; retain this legacy response shape.
    from routes.simplify_text_routes import simplify_text
    response, status = simplify_text()
    payload = response.get_json()
    if status != 200:
        return jsonify(success=False, error=payload.get('error', 'Simplification unavailable.')), status
    return jsonify(success=True, original_text=payload['originalText'],
                   formatted_text=payload['simplifiedText'], provider=payload['provider'],
                   changed=payload['changed'], notice=payload['notice'],
                   **({'structured_content': payload['structured_content']} if 'structured_content' in payload else {})), 200
