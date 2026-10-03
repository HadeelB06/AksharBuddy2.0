"""Incremental native-text extraction, with bounded raster OCR for scanned pages."""
import pymupdf as fitz
from PIL import Image
from .ocr_service import extract_text_from_pil
from .response import build_response, build_error
from modules.performance import span, report

MAX_SIZE_MB = 20

def process_pdf(file_storage, language='en'):
    if file_storage is None or not (file_storage.filename or '').lower().endswith('.pdf'):
        return build_error('pdf', 'Choose a PDF file.')
    data = file_storage.read(MAX_SIZE_MB * 1024 * 1024 + 1)
    if not data or len(data) > MAX_SIZE_MB * 1024 * 1024:
        return build_error('pdf', 'Choose a non-empty PDF smaller than 20 MB.')
    parts = []
    try:
        with fitz.open(stream=data, filetype='pdf') as doc:
            if doc.needs_pass:
                return build_error('pdf', 'Unlock the PDF before opening it.')
            if not 0 < doc.page_count <= 100:
                return build_error('pdf', 'Choose a PDF with 1 to 100 pages.')
            for index, page in enumerate(doc):
                report('Reading page', page=index+1, pages=doc.page_count)
                with span('pdf_native_text'):
                    text = page.get_text().strip()
                # A short native-text page is still native text, not a scan.
                if not text or '\ufffd' in text:
                    with span('pdf_rasterize'):
                        scale = min(200 / 72, 2400 / max(page.rect.width, page.rect.height))
                        pix = page.get_pixmap(matrix=fitz.Matrix(scale, scale), colorspace=fitz.csRGB, alpha=False)
                        image = Image.frombytes('RGB', (pix.width, pix.height), pix.samples)
                    text = extract_text_from_pil(image, language)
                parts.append(text)
                report('Page complete', page=index+1, pages=doc.page_count,
                       completedPages=index+1)
    except RuntimeError as exc:
        return build_error('pdf', f'Page {len(parts)+1} could not be read. No incomplete document was saved. {exc}')
    except Exception:
        return build_error('pdf', f'Could not read page {len(parts)+1}. Check that the PDF is valid.')
    combined = '\n\n'.join(parts).strip()
    if not combined:
        return build_error('pdf', 'No text found. Try a clearer scan.')
    return build_response('pdf', combined)
