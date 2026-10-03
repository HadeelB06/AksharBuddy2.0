"""Request-local timing/progress, without logging document contents."""
import contextvars
import logging
import time
from contextlib import contextmanager

trace = contextvars.ContextVar('ocr_trace', default=None)
progress = contextvars.ContextVar('ocr_progress', default=None)

@contextmanager
def span(name):
    start = time.perf_counter()
    try:
        yield
    finally:
        elapsed = time.perf_counter() - start
        current = trace.get()
        if current is not None:
            current[name] = round(current.get(name, 0) + elapsed, 4)
        logging.getLogger(__name__).info('stage=%s seconds=%.4f', name, elapsed)

def report(stage, **details):
    callback = progress.get()
    if callback:
        callback(stage, **details)
