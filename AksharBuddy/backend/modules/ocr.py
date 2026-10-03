import cv2
import numpy as np
from PIL import Image, ImageOps
import os
from .performance import span, report
import pytesseract

import logging
import threading

os.environ.setdefault('OMP_THREAD_LIMIT', '2')
_recognition_lock = threading.Lock()
reader = None
EASYOCR_AVAILABLE = True
_reader_lock = threading.Lock()


def _get_reader():
    """Load models once, only for an English/Hindi non-grid OCR request."""
    global reader, EASYOCR_AVAILABLE
    if not EASYOCR_AVAILABLE:
        return None
    if reader is not None:
        return reader
    with _reader_lock:
        if reader is None and EASYOCR_AVAILABLE:
            try:
                import torch
                torch.set_num_threads(2)
                import easyocr
                with span('ocr_model_initialization'):
                    reader = easyocr.Reader(['en', 'hi'], gpu=False, download_enabled=False)
            except Exception:
                EASYOCR_AVAILABLE = False
                logging.getLogger(__name__).warning('EasyOCR unavailable; using Tesseract.')
    return reader


def preprocess_image(image_np):
    if len(image_np.shape) == 3:
        # PIL supplies RGB arrays. Treating them as BGR subtly damages
        # colour-to-gray conversion before OCR.
        gray = cv2.cvtColor(image_np, cv2.COLOR_RGB2GRAY)
    else:
        gray = image_np

    height, width = gray.shape

    if height < 1000 or width < 1000:
        gray = cv2.resize(
            gray, None, fx=1.5, fy=1.5,
            interpolation=cv2.INTER_CUBIC
        )

    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)

    denoised = cv2.fastNlMeansDenoising(enhanced, h=10)

    thresh = cv2.adaptiveThreshold(
        denoised,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        11,
        2
    )

    return thresh


def _tesseract_language(language):
    language = (language or "en").lower()
    if language == "hi":
        return "hin+eng"
    if language == "mr":
        return "mar+eng"
    return "eng"


def _tesseract_detections(image, language, psm=3):
    """Return OCR words with their positions instead of flattening them."""
    data = pytesseract.image_to_data(
        image,
        lang=_tesseract_language(language),
        config=f"--oem 3 --psm {psm}",
        output_type=pytesseract.Output.DICT,
        timeout=45,
    )

    detections = []
    for index, value in enumerate(data.get("text", [])):
        text = value.strip()
        if not text:
            continue
        detections.append({
            "text": text,
            "left": int(data["left"][index]),
            "top": int(data["top"][index]),
            "width": int(data["width"][index]),
            "height": int(data["height"][index]),
            "confidence": float(data["conf"][index]),
            "lineKey": (
                int(data["block_num"][index]),
                int(data["par_num"][index]),
                int(data["line_num"][index]),
            ),
            "order": index,
        })
    return detections


def _render_detections(detections):
    """Render positioned OCR words into lines while keeping column gaps."""
    grouped = []
    by_key = {}
    for detection in detections:
        key = detection.get("lineKey", detection.get("order", 0))
        if key not in by_key:
            by_key[key] = []
            grouped.append(by_key[key])
        by_key[key].append(detection)

    rendered = []
    for words in grouped:
        words.sort(key=lambda item: item["left"])
        pieces = []
        previous_right = None
        for word in words:
            if previous_right is not None:
                gap = word["left"] - previous_right
                pieces.append("  " if gap >= max(18, word["width"] * 0.7) else " ")
            pieces.append(word["text"])
            previous_right = word["left"] + word["width"]
        rendered.append("".join(pieces))
    return "\n".join(rendered).strip()


def _layout_text_from_tesseract(image, language):
    """Compatibility wrapper returning layout-preserving OCR text."""
    return _render_detections(_tesseract_detections(image, language))


def _group_line_positions(mask, axis, threshold_ratio=0.35):
    """Find contiguous x/y positions occupied by strong table lines."""
    projection = mask.sum(axis=axis)
    limit = (mask.shape[axis] * 255) * threshold_ratio
    occupied = projection > limit
    groups = []
    start = None
    for index, present in enumerate(occupied):
        if present and start is None:
            start = index
        if (not present or index == len(occupied) - 1) and start is not None:
            end = index if present and index == len(occupied) - 1 else index - 1
            groups.append((start + end) // 2)
            start = None
    return groups


def _detect_table_grid(gray):
    """Detect substantial horizontal and vertical table rules."""
    binary = cv2.threshold(gray, 200, 255, cv2.THRESH_BINARY_INV)[1]
    horizontal_kernel = cv2.getStructuringElement(
        cv2.MORPH_RECT, (max(20, gray.shape[1] // 25), 1)
    )
    vertical_kernel = cv2.getStructuringElement(
        cv2.MORPH_RECT, (1, max(20, gray.shape[0] // 15))
    )
    horizontal = cv2.morphologyEx(binary, cv2.MORPH_OPEN, horizontal_kernel)
    vertical = cv2.morphologyEx(binary, cv2.MORPH_OPEN, vertical_kernel)
    x_lines = _group_line_positions(vertical, axis=0)
    y_lines = _group_line_positions(horizontal, axis=1)
    if len(x_lines) < 3 or len(y_lines) < 3:
        return None

    # Require the rules to meet repeatedly. Independent page decorations can
    # produce several horizontal and vertical strokes without forming cells.
    intersection_hits = 0
    for x_line in x_lines:
        for y_line in y_lines:
            y_start = max(0, y_line - 1)
            y_end = min(gray.shape[0], y_line + 2)
            x_start = max(0, x_line - 1)
            x_end = min(gray.shape[1], x_line + 2)
            if (
                vertical[y_start:y_end, x_start:x_end].any()
                and horizontal[y_start:y_end, x_start:x_end].any()
            ):
                intersection_hits += 1
    if intersection_hits < max(4, len(x_lines) * len(y_lines) * 0.5):
        return None

    return {
        "xLines": x_lines,
        "yLines": y_lines,
        "horizontalMask": horizontal,
        "verticalMask": vertical,
    }


def _remove_table_lines(gray, grid):
    """Remove detected rules while leaving text pixels intact for OCR."""
    rules = cv2.bitwise_or(grid["horizontalMask"], grid["verticalMask"])
    return cv2.inpaint(gray, rules, 3, cv2.INPAINT_TELEA)


def _easyocr_detections(results):
    detections = []
    for order, result in enumerate(results):
        bounding_box, text, confidence = result
        text = text.strip()
        if not text:
            continue
        xs = [point[0] for point in bounding_box]
        ys = [point[1] for point in bounding_box]
        left, right = min(xs), max(xs)
        top, bottom = min(ys), max(ys)
        detections.append({
            "text": text,
            "left": int(left),
            "top": int(top),
            "width": int(right - left),
            "height": int(bottom - top),
            "confidence": float(confidence),
            "lineKey": order,
            "order": order,
        })
    return detections


def _layout_text_from_easyocr(results):
    """Group EasyOCR boxes into lines instead of flattening them."""
    words = []
    for bounding_box, text, _confidence in results:
        if not text.strip():
            continue
        xs = [point[0] for point in bounding_box]
        ys = [point[1] for point in bounding_box]
        words.append((
            min(xs),
            min(ys),
            max(xs),
            max(ys),
            text.strip(),
        ))

    words.sort(key=lambda item: (item[1], item[0]))
    lines = []
    for word in words:
        center_y = (word[1] + word[3]) / 2
        matching_line = None
        for line in lines:
            if abs(center_y - line["center_y"]) <= max(12, word[3] - word[1]):
                matching_line = line
                break
        if matching_line is None:
            matching_line = {"center_y": center_y, "words": []}
            lines.append(matching_line)
        matching_line["words"].append(word)

    rendered = []
    for line in lines:
        line["words"].sort(key=lambda item: item[0])
        rendered.append(" ".join(word[4] for word in line["words"]))
    return "\n".join(rendered).strip()


def _deskew_image(image):
    """Conservative projection-based deskew for sparse, document-like pages."""
    gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
    scale = min(1.0, 800.0 / max(gray.shape))
    small = cv2.resize(gray, None, fx=scale, fy=scale)
    _, ink = cv2.threshold(small, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    ratio = np.count_nonzero(ink) / ink.size
    if not 0.003 < ratio < 0.30:
        return image
    h, w = ink.shape
    scores = []
    for angle in range(-12, 13):
        matrix = cv2.getRotationMatrix2D((w / 2, h / 2), angle, 1)
        rotated = cv2.warpAffine(ink, matrix, (w, h), flags=cv2.INTER_NEAREST)
        projection = np.sum(rotated > 0, axis=1).astype(float)
        scores.append(float(np.sum(projection ** 2)))
    best = int(np.argmax(scores))
    angle = best - 12
    if abs(angle) < 2 or abs(angle) == 12 or scores[best] < scores[12] * 1.30:
        return image
    h, w = image.shape[:2]
    matrix = cv2.getRotationMatrix2D((w / 2, h / 2), angle, 1)
    cosine, sine = abs(matrix[0, 0]), abs(matrix[0, 1])
    width, height = int(h * sine + w * cosine), int(h * cosine + w * sine)
    matrix[0, 2] += width / 2 - w / 2
    matrix[1, 2] += height / 2 - h / 2
    return cv2.warpAffine(image, matrix, (width, height), borderValue=(255, 255, 255))


def extract_document(image_input, language="en"):
    """Extract text and a structure-aware display model from an image."""
    with span('decode_resize'):
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

    rendered_text = _render_detections(detections)
    from input_processing.structure_analyzer import analyze_structure

    structure = analyze_structure(
        image_np.shape,
        detections,
        {"xLines": grid["xLines"], "yLines": grid["yLines"]} if grid else None,
        rendered_text,
    )
    from input_processing.structure_analyzer import render_structure
    canonical_text = render_structure(structure) or rendered_text
    return {
        "text": canonical_text,
        "detections": detections,
        "structure": structure,
    }


def extract_text(image_input, language="en"):
    return extract_document(image_input, language)["text"]
