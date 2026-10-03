from pathlib import Path
p = Path(__file__).resolve().parents[1] / 'AksharBuddy' / 'backend'
f=p/'modules/ocr.py'
s=f.read_text(encoding='utf-8').replace('from PIL import Image','from PIL import Image, ImageOps\nimport os\nfrom .performance import span, report')
s=s.replace('reader = None', "os.environ.setdefault('OMP_THREAD_LIMIT', '2')\n_recognition_lock = threading.Lock()\nreader = None",1)
s=s.replace("import easyocr\n                reader = easyocr.Reader(['en', 'hi'], gpu=False)", "import torch\n                torch.set_num_threads(2)\n                import easyocr\n                with span('ocr_model_initialization'):\n                    reader = easyocr.Reader(['en', 'hi'], gpu=False, download_enabled=False)")
s=s.replace('output_type=pytesseract.Output.DICT,','output_type=pytesseract.Output.DICT,\n        timeout=45,')
a=s.index('    if isinstance(image_input, np.ndarray):',s.index('def extract_document'))
b=s.index('    rendered_text =',a)
s=s[:a]+'''    with span('decode_resize'):
        if isinstance(image_input, np.ndarray):
            image = Image.fromarray(image_input)
        elif isinstance(image_input, Image.Image):
            image = image_input
        else:
            image = Image.open(image_input)
            image.draft('RGB', (2400, 2400))
        image = ImageOps.exif_transpose(image)
        image.thumbnail((2400, 2400), Image.Resampling.LANCZOS)
        image_np = np.array(image.convert('RGB'))
    report('Extracting text')
    with span('preprocessing'):
        image_np = _deskew_image(image_np)
        gray = cv2.cvtColor(image_np, cv2.COLOR_RGB2GRAY)
        grid = _detect_table_grid(gray)
        ocr_image = _remove_table_lines(gray, grid) if grid else gray

    # Printed documents use the much faster, installed offline recognizer.
    # EasyOCR remains a cached fallback for captures Tesseract cannot read.
    with span('ocr_recognition'):
        detections = _tesseract_detections(ocr_image, language, psm=6 if grid else 3)
    if not detections and np.std(gray) > 5 and not grid and language in ('en', 'hi'):
        engine = _get_reader()
        if engine is not None:
            with _recognition_lock, span('easyocr_recognition'):
                detections = _easyocr_detections(engine.readtext(
                    image_np, detail=1, paragraph=False, workers=0,
                    batch_size=1, canvas_size=2000))
    if not detections and np.std(gray) > 5:
        with span('preprocessing_retry'):
            enhanced = preprocess_image(image_np)
        with span('ocr_retry'):
            detections = _tesseract_detections(enhanced, language)

'''+s[b:]
f.write_text(s,encoding='utf-8')
f=p/'input_processing/ocr_service.py'
f.write_text('''"""Shared OCR entry points; decode and resize once in the recognizer."""
import io
from modules.ocr import extract_document

def extract_document_from_bytes(image_bytes, language='en'):
    return extract_document(io.BytesIO(image_bytes), language)

def extract_text_from_bytes(image_bytes, language='en'):
    return extract_document_from_bytes(image_bytes, language)['text']

def extract_text_from_pil(pil_image, language='en'):
    return extract_document(pil_image, language)['text']
''',encoding='utf-8')
(p/'input_processing/pdf_processor.py').write_text('''"""Incremental native-text extraction, with bounded raster OCR for scanned pages."""
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
                if not text or '\\ufffd' in text:
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
    combined = '\\n\\n'.join(parts).strip()
    if not combined:
        return build_error('pdf', 'No text found. Try a clearer scan.')
    return build_response('pdf', combined)
''',encoding='utf-8')
f=p/'run_local.py';s=f.read_text(encoding='utf-8').replace('import sys','import sys\nimport os\nimport logging\nlogging.basicConfig(level=logging.INFO)');s=s.replace("host='127.0.0.1', port=5000", "host='0.0.0.0', port=int(os.environ.get('PORT', '5000'))");f.write_text(s,encoding='utf-8')
f=p/'app.py';s=f.read_text(encoding='utf-8').replace('CORS(app)', "CORS(app)\napp.config['MAX_CONTENT_LENGTH'] = 21 * 1024 * 1024\nfrom routes.extraction_jobs import jobs_bp\napp.register_blueprint(jobs_bp)").replace('"service": "aksharbuddy"','"service": "aksharbuddy", "version": "lan-repair-1", "offline": True').replace('host="127.0.0.1"','host="0.0.0.0"');f.write_text(s,encoding='utf-8')
