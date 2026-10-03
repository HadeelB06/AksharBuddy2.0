"""
Input Router — inspects the incoming Flask request and delegates to the
correct processor.  This is the single entry-point called by the route.

Decision logic:
  - If the request has a 'text' field (form or JSON) and no file → text
  - If the request has a file named 'file':
      · .pdf  → pdf_processor
      · .docx → docx_processor
      · image extensions → image_processor (covers uploads + camera captures)
  - Anything else → error
"""

from flask import Request

from .text_processor import process_text
from .image_processor import process_image, ALLOWED_EXTENSIONS as IMAGE_EXTS
from .pdf_processor import process_pdf
from .docx_processor import process_docx
from .response import build_error


def route_input(request: Request, language: str = "en") -> dict:
    """
    Inspect the Flask request and call the appropriate processor.

    Accepted request shapes
    -----------------------
    Direct text   — form field 'text'  OR  JSON body {"text": "..."}
    Image upload  — multipart file field 'file'  (.jpg / .jpeg / .png / .webp)
    Camera image  — same as image upload (frontend sends it as 'file')
    PDF           — multipart file field 'file'  (.pdf)
    DOCX          — multipart file field 'file'  (.docx)
    """

    # ── 1. Direct text input ────────────────────────────────────────────────
    text_value = None

    if request.is_json:
        body = request.get_json(silent=True) or {}
        text_value = body.get("text")
    else:
        text_value = request.form.get("text")

    # If text is provided and there is no file, treat as direct text input
    if text_value is not None and "file" not in request.files:
        return process_text(text_value)

    # ── 2. File-based input ──────────────────────────────────────────────────
    file = request.files.get("file")

    if file is None or file.filename == "":
        # Nothing supplied at all
        return build_error("unknown", "No input provided. Send a 'text' field or a 'file' upload.")

    filename = file.filename.lower()

    if filename.endswith(".pdf"):
        return process_pdf(file, language)

    if filename.endswith(".docx"):
        return process_docx(file)

    if any(filename.endswith(ext) for ext in IMAGE_EXTS):
        return process_image(file, language)

    return build_error(
        "unknown",
        f"Unsupported file type '{filename.rsplit('.', 1)[-1]}'. "
        f"Allowed: jpg, jpeg, png, webp, pdf, docx."
    )
