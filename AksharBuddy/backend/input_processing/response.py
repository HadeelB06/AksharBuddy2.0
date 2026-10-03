"""
Response helpers — every processor returns the exact same shape so callers
never need to check for different dict structures.
"""


def build_response(source_type: str, extracted_text: str, structured_content=None) -> dict:
    """Build a successful standard response."""
    response = {
        "status": "success",
        "sourceType": source_type,
        "extractedText": extracted_text,
        "characterCount": len(extracted_text),
        "wordCount": len(extracted_text.split()),
    }
    if structured_content is not None:
        response["structuredContent"] = structured_content
    return response


def build_error(source_type: str, message: str) -> dict:
    """Build a failed standard response."""
    return {
        "status": "error",
        "sourceType": source_type,
        "extractedText": "",
        "characterCount": 0,
        "wordCount": 0,
        "error": message,
    }
