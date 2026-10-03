"""
Image Processor — handles JPG, JPEG, PNG, and WEBP uploads as well as
images captured from the device camera (which arrive as the same file
types, so no extra handling is needed on the backend).
"""

from .ocr_service import extract_document_from_bytes
from .response import build_response, build_error

ALLOWED_MIME_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
MAX_SIZE_MB = 10


def process_image(file_storage, language: str = "en") -> dict:
    """
    Accept a Werkzeug FileStorage object (from Flask's request.files),
    validate it, read the bytes, and run OCR.

    Works identically for both uploaded images and camera captures.
    """
    if file_storage is None or file_storage.filename == "":
        return build_error("image", "No image file provided.")

    filename = file_storage.filename.lower()
    if not any(filename.endswith(ext) for ext in ALLOWED_EXTENSIONS):
        return build_error(
            "image",
            f"Unsupported file type. Allowed: {', '.join(ALLOWED_EXTENSIONS)}"
        )

    image_bytes = file_storage.read()

    if not image_bytes:
        return build_error("image", "Uploaded image file is empty.")

    size_mb = len(image_bytes) / (1024 * 1024)
    if size_mb > MAX_SIZE_MB:
        return build_error("image", f"File too large ({size_mb:.1f} MB). Max is {MAX_SIZE_MB} MB.")

    try:
        extracted = extract_document_from_bytes(image_bytes, language)
    except Exception as e:
        return build_error("image", f"OCR failed: {str(e)}")

    if not extracted.get("text"):
        return build_error("image", "No text could be detected in the image.")

    return build_response("image", extracted["text"], extracted.get("structure"))
