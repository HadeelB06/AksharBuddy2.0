"""The supplied simplification model has no dictionary training."""
from flask import Blueprint, request
word_bp = Blueprint('word_help', __name__)
@word_bp.post('/api/word-help')
def word_help():
    data = request.get_json(silent=True)
    if not isinstance(data, dict) or not isinstance(data.get('word'), str) or data.get('language', 'en') not in ('en','hi','mr'):
        return {'error': 'Choose a word and English, Hindi or Marathi.'}, 400
    return {'error': 'This local model does not provide verified word definitions. Saved meanings remain available offline.'}, 422
