"""Bounded, single-worker extraction with polling; never invokes simplification."""
import io
import secrets
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace
from flask import Blueprint, request, jsonify
from werkzeug.datastructures import FileStorage
from input_processing.input_router import route_input
from input_processing.dyslexia_formatter import format_text
from modules.performance import trace, progress

jobs_bp = Blueprint('extraction_jobs', __name__)
_pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix='ocr')
_lock = threading.Lock()
_jobs = {}

def _work(key, data, filename, language, profile):
    timings = {}
    def update(stage, **details):
        with _lock:
            job = _jobs[key]
            if job['state'] == 'cancelled':
                raise RuntimeError('Reading cancelled.')
            job.update(stage=stage, **details)
    t = trace.set(timings)
    p = progress.set(update)
    start = time.perf_counter()
    try:
        update('Extracting text')
        upload = FileStorage(io.BytesIO(data), filename=filename)
        fake_request = SimpleNamespace(is_json=False, form={}, files={'file': upload})
        extraction = route_input(fake_request, language)
        if extraction.get('status') != 'success':
            raise ValueError(extraction.get('error') or extraction.get('message') or 'Could not extract text.')
        raw = extraction['extractedText']
        formatting = format_text(raw, profile)
        result = dict(formatting['readingProfile'], status='success',
                      sourceType=extraction['sourceType'], originalText=raw,
                      processedText=formatting['formattedText'],
                      structuredContent=extraction.get('structuredContent'),
                      metadata=formatting['metadata'], timings=timings)
        with _lock:
            if _jobs[key]['state'] != 'cancelled':
                _jobs[key].update(state='complete', stage='Ready to check', result=result)
    except Exception as exc:
        with _lock:
            if _jobs[key]['state'] != 'cancelled':
                _jobs[key].update(state='failed', error=str(exc), stage='Could not read this file')
    finally:
        with _lock:
            _jobs[key]['seconds'] = round(time.perf_counter()-start, 3)
            _jobs[key]['finished'] = time.monotonic()
        trace.reset(t)
        progress.reset(p)

@jobs_bp.post('/api/extraction-jobs')
def create_job():
    language = request.form.get('language', 'en')
    if language not in ('en', 'hi', 'mr'):
        return jsonify(status='error', error='Choose English, Hindi or Marathi.'), 400
    upload = request.files.get('file')
    if upload is None or not upload.filename:
        return jsonify(status='error', error='Choose a file.'), 400
    data = upload.read(20*1024*1024+1)
    if not data or len(data) > 20*1024*1024:
        return jsonify(status='error', error='Choose a non-empty file smaller than 20 MB.'), 400
    with _lock:
        now = time.monotonic()
        for key in list(_jobs):
            finished = _jobs[key].get('finished')
            if finished is not None and now-finished > 600:
                del _jobs[key]
        active = sum('finished' not in j for j in _jobs.values())
        if active >= 3 or len(_jobs) >= 30:
            return jsonify(status='error', error='The laptop is busy. Try again shortly.'), 429
        key = secrets.token_urlsafe(24)
        _jobs[key] = dict(status='success', state='working', stage='Waiting for OCR', created=now)
    _pool.submit(_work, key, data, upload.filename, language, request.form.get('profile', 'moderate'))
    return jsonify(status='success', jobId=key), 202

@jobs_bp.get('/api/extraction-jobs/<key>')
def get_job(key):
    with _lock:
        job = _jobs.get(key)
        if job is None:
            return jsonify(status='error', error='Reading expired. Please select the file again.'), 404
        return jsonify(job)

@jobs_bp.delete('/api/extraction-jobs/<key>')
def cancel_job(key):
    with _lock:
        if key in _jobs:
            _jobs[key].update(state='cancelled', stage='Cancelled')
    return jsonify(status='success')
