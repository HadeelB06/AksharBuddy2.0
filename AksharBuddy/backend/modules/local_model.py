"""Local IndicBART inference: no cloud generation, downloading or API fallback."""
from pathlib import Path
import copy
import os
import re
import threading
from .performance import span
from .output_guard import validate

MODEL_DIR = Path(os.environ.get('AKSHARBUDDY_MODEL_PATH', Path(__file__).resolve().parents[1] / 'models' / 'aksharbuddy-indicbart'))
_model = None
_tokenizer = None
_lock = threading.Lock()

def _load():
    global _model, _tokenizer
    if _model is not None:
        return
    if not (MODEL_DIR / 'model.safetensors').is_file():
        raise RuntimeError('Local model files are missing. Run setup.')
    import torch
    from transformers import MBartForConditionalGeneration, PreTrainedTokenizerFast
    torch.set_num_threads(2)
    tokenizer = PreTrainedTokenizerFast(tokenizer_file=str(MODEL_DIR / 'tokenizer.json'), unk_token='<unk>', pad_token='<pad>')
    model = MBartForConditionalGeneration.from_pretrained(str(MODEL_DIR), local_files_only=True, use_safetensors=True, dtype=torch.float32)
    model.eval()
    _tokenizer, _model = tokenizer, model

def _validate_output(original, candidate, language):
    validate(original, candidate, language)
    if not candidate.strip():
        raise ValueError('The model did not produce readable text. Your original is preserved.')
    if re.findall(r'\d+(?:[.,]\d+)*', original) != re.findall(r'\d+(?:[.,]\d+)*', candidate):
        raise ValueError('The model changed a number. Your original is preserved.')
    negatives = {'en': ['not', 'never', 'without', 'no'], 'hi': ['नहीं', 'मत', 'बिना'], 'mr': ['नाही', 'नको', 'नयेत', 'नये']}[language]
    for word in negatives:
        if word in original.lower().split() and word not in candidate.lower().split():
            raise ValueError('The model may have changed a negative instruction. Your original is preserved.')
    if language == 'en' and re.search(r'[\u0900-\u097f]', candidate):
        raise ValueError('The model changed the language. Your original is preserved.')
    if language in ('hi', 'mr') and re.search(r'[\u0900-\u097f]', original) and not re.search(r'[\u0900-\u097f]', candidate):
        raise ValueError('The model changed the script. Your original is preserved.')
    words = candidate.split()
    if len(words) > 12 and len(set(words)) < len(words) / 4:
        raise ValueError('The model produced repetitive text. Your original is preserved.')

def process_text(text, language='en'):
    if language not in ('en', 'hi', 'mr'):
        raise ValueError('Choose English, Hindi or Marathi.')
    if not isinstance(text, str) or not text.strip():
        return ''
    if len(text) > 12000:
        raise ValueError('Select fewer than 12,000 characters.')
    if not _lock.acquire(blocking=False):
        raise RuntimeError('The local model is busy. Try again shortly.')
    try:
        with span('model_load_or_reuse'):
            _load()
        import torch
        tok = _tokenizer
        lang_id = tok.convert_tokens_to_ids(f'<2{language}>')
        end_id = tok.convert_tokens_to_ids('</s>')
        output = []
        for paragraph in text.strip().split('\n'):
            if not paragraph.strip():
                output.append('')
                continue
            rewritten = []
            for sentence in re.split(r'(?<=[.!?।])\s+', paragraph.strip()):
                inputs = tok(f'{sentence} </s> <2{language}>', add_special_tokens=False, return_tensors='pt', return_token_type_ids=False)
                length = inputs['input_ids'].shape[1]
                if length > 384:
                    raise ValueError('A sentence is too long. Split it into shorter sentences in the text editor.')
                with torch.inference_mode(), span('model_inference'):
                    result = _model.generate(**inputs, decoder_start_token_id=lang_id, eos_token_id=end_id, pad_token_id=tok.pad_token_id, forced_eos_token_id=None, max_new_tokens=min(768, max(64, length * 2 + 24)), num_beams=2, do_sample=False, use_cache=True)
                ids = result[0].tolist()
                if ids[-1] != end_id:
                    raise ValueError('Model output was incomplete. Your original is preserved.')
                candidate = tok.decode([i for i in ids if i not in {lang_id, end_id, 64000, tok.pad_token_id}], skip_special_tokens=True).strip()
                _validate_output(sentence, candidate, language)
                rewritten.append(candidate)
            output.append(' '.join(rewritten))
        return '\n'.join(output)
    finally:
        _lock.release()

def process_structured_content(structure, language='en'):
    candidate = copy.deepcopy(structure)
    for block in candidate.get('blocks', []):
        if block.get('type') == 'paragraph':
            block['text'] = process_text(block.get('text', ''), language)
        elif block.get('type') == 'section':
            block['lines'] = [process_text(line, language) for line in block.get('lines', [])]
        elif block.get('type') == 'menu_section':
            for item in block.get('items', []):
                if item.get('description'):
                    item['description'] = process_text(item['description'], language)
    return candidate
