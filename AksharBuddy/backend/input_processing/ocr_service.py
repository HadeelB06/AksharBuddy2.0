"""Shared OCR entry points; decode and resize once in the recognizer."""
import io
from modules.ocr import extract_document

def extract_document_from_bytes(image_bytes, language='en'):
    return extract_document(io.BytesIO(image_bytes), language)

def extract_text_from_bytes(image_bytes, language='en'):
    return extract_document_from_bytes(image_bytes, language)['text']

def extract_text_from_pil(pil_image, language='en'):
    return extract_document(pil_image, language)['text']
