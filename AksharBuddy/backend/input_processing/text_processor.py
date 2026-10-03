"""
Text Processor — handles direct text input from the user.
Validates that the text is non-empty and returns the standard response.
"""

import re
from .response import build_response, build_error


def process_text(text: str) -> dict:
    """
    Validate and lightly clean manually-entered text.

    Steps:
      1. Strip leading/trailing whitespace.
      2. Collapse runs of whitespace to single spaces.
      3. Reject if the result is empty.
    """
    if not isinstance(text, str):
        return build_error("text", "Input must be a string.")

    cleaned = re.sub(r"\s+", " ", text.strip())

    if not cleaned:
        return build_error("text", "Text input is empty.")

    return build_response("text", cleaned)
