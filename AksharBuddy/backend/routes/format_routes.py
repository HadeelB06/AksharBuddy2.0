"""
Format Routes — POST /api/format-text

Extracts text from any supported source (typed text, image, camera capture,
PDF, DOCX) and applies dyslexia-friendly formatting.

This endpoint NEVER simplifies, rewrites, translates, or summarises text.
Words are preserved exactly as extracted. Only visual structure is adjusted.
"""

from flask import Blueprint, request, jsonify

from input_processing.input_router import route_input
from input_processing.dyslexia_formatter import format_text, PROFILES, DEFAULT_PROFILE

format_bp = Blueprint("format", __name__)


@format_bp.route("/api/format-text", methods=["POST"])
def format_text_endpoint():
    """
    Extract text and apply dyslexia-friendly formatting. Words are never changed.
    ---
    tags:
      - Dyslexia Formatter
    consumes:
      - multipart/form-data
      - application/json
    parameters:
      - in: query
        name: language
        type: string
        enum: [en, hi, mr]
        default: en
        description: OCR language for image/PDF input
      - in: formData
        name: profile
        type: string
        enum: [mild, moderate, severe]
        default: moderate
        description: Reading profile — controls font size, line height, letter spacing, and word spacing
      - in: formData
        name: text
        type: string
        description: >
          Already-extracted plain text to format. Send this WITHOUT a 'file'
          field to skip OCR and go straight to formatting.
        example: As he leaned down he saw his reflection in the water and gasped in surprise.
      - in: formData
        name: file
        type: file
        description: >
          File to extract and format. Supported: JPG, JPEG, PNG, WEBP, PDF, DOCX.
    responses:
      200:
        description: Text extracted and formatted successfully
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
            originalText:
              type: string
              example: As he leaned down he saw his reflection in the water.
            processedText:
              type: string
              example: "As he leaned down he saw his reflection\nin the water and gasped in surprise.\n\nThe image stared back at him."
            profile:
              type: string
              example: moderate
            fontSize:
              type: number
              example: 20.0
            lineHeight:
              type: number
              example: 1.8
            letterSpacing:
              type: number
              example: 1.0
            wordSpacing:
              type: number
              example: 4.0
            paragraphSpacing:
              type: number
              example: 16.0
            recommendedFont:
              type: string
              example: Lexend
            metadata:
              type: object
              properties:
                wordCount:
                  type: integer
                  example: 120
                characterCount:
                  type: integer
                  example: 680
                paragraphCount:
                  type: integer
                  example: 4
                estimatedReadingTimeSeconds:
                  type: integer
                  example: 55
      400:
        description: Extraction failed or no input provided
    """
    # Read language and profile from query string, form, or JSON body
    json_body = request.get_json(silent=True) or {}
    language  = (request.args.get("language")
                 or request.form.get("language")
                 or json_body.get("language", "en"))
    profile   = (request.args.get("profile")
                 or request.form.get("profile")
                 or json_body.get("profile", DEFAULT_PROFILE))

    # ── Step 1: extract raw text ─────────────────────────────────────────────
    extraction = route_input(request, language)

    if extraction.get("status") != "success":
        return jsonify(extraction), 400

    raw_text    = extraction["extractedText"]
    source_type = extraction["sourceType"]

    # ── Step 2: apply dyslexia formatting (no AI, no rewrites) ───────────────
    formatting  = format_text(raw_text, profile)
    rp          = formatting["readingProfile"]   # already stripped of internal keys

    # ── Step 3: return flat response — all typography fields at the top level
    # so Flutter's FormatResult.fromJson() can read them without any mapping.
    return jsonify({
        "status":           "success",
        "sourceType":       source_type,
        "originalText":     raw_text,
        # FormatResult fields (flat, matching FormatResult.fromJson exactly)
        "processedText":    formatting["formattedText"],
        "profile":          rp["profile"],
        "fontSize":         rp["fontSize"],
        "lineHeight":       rp["lineHeight"],
        "letterSpacing":    rp["letterSpacing"],
        "wordSpacing":      rp["wordSpacing"],
        "paragraphSpacing": rp["paragraphSpacing"],
        "recommendedFont":  rp["recommendedFont"],
        "structuredContent": extraction.get("structuredContent"),
        # Extra info the Flutter client can use or ignore
        "metadata":         formatting["metadata"],
    }), 200
