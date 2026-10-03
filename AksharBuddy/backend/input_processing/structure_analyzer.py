"""Layout analysis for OCR results.

The analyzer deliberately works from OCR boxes rather than guessed punctuation.
That lets the API preserve empty table cells, column order, and menu
relationships even when OCR gets a symbol or a word slightly wrong.
"""

import re


_PRICE_TOKEN = re.compile(
    r"^(?:₹|Rs\.?|INR|%|X|x|¥|Y)?\s*[0-9][0-9,]*(?:\.[0-9]+)?$",
    re.IGNORECASE,
)


def _text(words):
    return " ".join(word["text"] for word in sorted(words, key=lambda item: item["left"])).strip()


def _line_groups(detections):
    if not detections:
        return []
    lines = []
    for word in sorted(detections, key=lambda item: (item["top"], item["left"])):
        center_y = word["top"] + word["height"] / 2
        word_height = max(1, word["height"])
        word_bottom = word["top"] + word_height
        line = next((candidate for candidate in lines
                     if _belongs_to_line(
                         center_y,
                         word_height,
                         word["top"],
                         word_bottom,
                         candidate,
                     )), None)
        if line is None:
            line = {
                "centerY": center_y,
                "top": word["top"],
                "bottom": word_bottom,
                "words": [],
            }
            lines.append(line)
        line["words"].append(word)
        line["centerY"] = sum(
            item["top"] + item["height"] / 2 for item in line["words"]
        ) / len(line["words"])
        line["top"] = min(item["top"] for item in line["words"])
        line["bottom"] = max(item["top"] + item["height"] for item in line["words"])
    for line in lines:
        line["words"].sort(key=lambda item: item["left"])
        line["text"] = _text(line["words"])
        line["left"] = min(item["left"] for item in line["words"])
        line["right"] = max(item["left"] + item["width"] for item in line["words"])
    return sorted(lines, key=lambda item: item["centerY"])


def _belongs_to_line(center_y, word_height, word_top, word_bottom, line):
    """Use vertical overlap, not a broad global tolerance, to form lines.

    A tolerance based on the median OCR height can merge two closely-spaced
    lines (especially a short heading and the line below it). Matching the
    vertical span of the candidate word to the existing line keeps words on
    the same baseline together while preserving the document's row order.
    """
    line_height = max(1, line["bottom"] - line["top"])
    overlap = max(0, min(word_bottom, line["bottom"]) -
                  max(word_top, line["top"]))
    overlap_ratio = overlap / min(word_height, line_height)
    center_distance = abs(center_y - line["centerY"])
    return overlap_ratio >= 0.30 or center_distance <= max(
        5.0, min(word_height, line_height) * 0.55
    )


def _is_heading(value):
    letters = [character for character in value if character.isalpha()]
    return len(letters) >= 3 and sum(character.isupper() for character in letters) / len(letters) >= 0.72


def _price_words(words):
    return [word for word in words if _PRICE_TOKEN.match(word["text"].replace(" ", ""))]


def _table_block(detections, grid):
    x_lines = grid["xLines"]
    y_lines = grid["yLines"]
    rows = []
    for row_index in range(len(y_lines) - 1):
        row = []
        for column_index in range(len(x_lines) - 1):
            words = []
            for word in detections:
                center_x = word["left"] + word["width"] / 2
                center_y = word["top"] + word["height"] / 2
                if (
                    x_lines[column_index] < center_x < x_lines[column_index + 1]
                    and y_lines[row_index] < center_y < y_lines[row_index + 1]
                ):
                    words.append(word)
            row.append(_text(words))
        rows.append(row)

    if not rows:
        return None
    header_text = " ".join(rows[0]).lower()
    return {
        "type": "table",
        "headers": rows[0],
        "rows": rows[1:],
        "columnCount": len(x_lines) - 1,
        "hasEmptyCells": any(not cell for row in rows for cell in row),
        "headerText": header_text,
    }


def _aligned_table_block(detections):
    """Recover borderless tables from repeated, multi-cell rows.

    Text that happens to contain words such as "price" is not enough to be a
    table. A borderless table must have a plausible header plus at least two
    subsequent rows with multiple consistently occupied columns.
    """
    lines = _line_groups(detections)
    header_index = next(
        (
            index for index, line in enumerate(lines)
            if len(line["words"]) >= 2
            and sum(
                any(keyword in word["text"].lower()
                    for keyword in ("item", "name", "quantity", "qty", "price",
                                    "amount", "cost", "notes", "date", "total"))
                for word in line["words"]
            ) >= 2
        ),
        None,
    )
    if header_index is None:
        return None

    header_words = lines[header_index]["words"]
    anchors = [
        word["left"] + word["width"] / 2
        for word in header_words
    ]
    if len(anchors) < 2:
        return None
    boundaries = [
        float("-inf"),
        *[(anchors[index] + anchors[index + 1]) / 2
          for index in range(len(anchors) - 1)],
        float("inf"),
    ]

    def cells_for_line(line):
        cells = [[] for _ in anchors]
        for word in line["words"]:
            center_x = word["left"] + word["width"] / 2
            column = next(
                index for index in range(len(anchors))
                if boundaries[index] <= center_x < boundaries[index + 1]
            )
            cells[column].append(word)
        return cells

    header_cells = cells_for_line(lines[header_index])
    if sum(bool(cell) for cell in header_cells) < 2:
        return None

    body_rows = []
    line_heights = [
        max(1, line["bottom"] - line["top"])
        for line in lines
    ]
    typical_height = sorted(line_heights)[len(line_heights) // 2]
    max_row_gap = max(70, typical_height * 3.5)
    previous_line = lines[header_index]
    for line in lines[header_index + 1:]:
        if line["top"] - previous_line["bottom"] > max_row_gap:
            break
        cells = cells_for_line(line)
        occupied = [index for index, cell in enumerate(cells) if cell]
        if len(occupied) >= 2:
            body_rows.append(cells)
        elif body_rows:
            # A later paragraph should not be absorbed into the table after
            # the repeated row pattern has ended.
            break
        previous_line = line

    if len(body_rows) < 2:
        return None

    repeated_columns = sum(
        sum(bool(row[index]) for row in body_rows) >= 2
        for index in range(len(anchors))
    )
    if repeated_columns < 2:
        return None

    rows = [[_text(cell) for cell in row] for row in body_rows]
    headers = [_text(cell) for cell in header_cells]
    return {
        "type": "table",
        "headers": headers,
        "rows": rows,
        "columnCount": len(headers),
        "hasEmptyCells": any(not cell for row in rows for cell in row),
        "headerText": " ".join(headers).lower(),
    }


def _columns(detections, image_width):
    if not detections or image_width < 2:
        return None

    lines = _line_groups(detections)
    # A real two-column layout has a repeated vertical gutter between words
    # on several lines. A long single-column line can cross the midpoint, so
    # splitting every word at image_width / 2 falsely creates two columns.
    minimum_gutter = max(24.0, image_width * 0.08)
    gutter_centers = []
    for line in lines:
        for previous, current in zip(line["words"], line["words"][1:]):
            gap_start = previous["left"] + previous["width"]
            gap_end = current["left"]
            gap = gap_end - gap_start
            if (
                gap >= minimum_gutter
                and gap_start < image_width * 0.68
                and gap_end > image_width * 0.32
            ):
                gutter_centers.append((gap_start + gap_end) / 2)

    if len(gutter_centers) < 3:
        return None

    split = sorted(gutter_centers)[len(gutter_centers) // 2]
    left = [
        item for item in detections
        if item["left"] + item["width"] / 2 < split
    ]
    right = [
        item for item in detections
        if item["left"] + item["width"] / 2 >= split
    ]
    if len(left) < 3 or len(right) < 3:
        return None
    span = max(item["left"] + item["width"] for item in detections) - min(item["left"] for item in detections)
    if span < image_width * 0.65 or split < image_width * 0.30 or split > image_width * 0.70:
        return None
    return [
        [_text(line["words"]) for line in _line_groups(left)],
        [_text(line["words"]) for line in _line_groups(right)],
    ]


def _looks_like_section_heading(lines, index):
    """Identify short heading lines using OCR text and nearby geometry.

    Uppercase headings are the strongest signal for Latin text. For scripts
    without casing, a short line that is visually separated from the next
    line or has a larger OCR box is also eligible. The following line is
    required so a document title or footer is not emitted as an empty section.
    """
    line = lines[index]
    if index >= len(lines) - 1 or not line["text"]:
        return False

    words = line["words"]
    if len(words) > 8 or len(line["text"]) > 90:
        return False

    if _is_heading(line["text"]):
        return True

    letters = [character for character in line["text"] if character.isalpha()]
    if not letters:
        return False

    # For scripts with upper/lowercase, a non-uppercase line is body text.
    # Geometry-only detection is reserved for scripts such as Devanagari,
    # where casing cannot provide the heading signal.
    cased_letters = [
        character for character in letters
        if character.lower() != character.upper()
    ]
    if cased_letters:
        return False

    following = lines[index + 1]
    gap = following["top"] - line["bottom"]
    current_height = max(1, line["bottom"] - line["top"])
    following_height = max(1, following["bottom"] - following["top"])
    return (
        len(words) <= 5
        and current_height >= following_height * 1.12
        and gap >= max(4, following_height * 0.35)
    )


def _section_blocks(detections):
    """Build heading-led sections from the spatially ordered OCR lines."""
    lines = _line_groups(detections)
    heading_indexes = [
        index for index in range(len(lines))
        if _looks_like_section_heading(lines, index)
    ]
    if not heading_indexes:
        return None

    blocks = []
    preamble = []
    current = None
    heading_set = set(heading_indexes)
    for index, line in enumerate(lines):
        if index in heading_set:
            if current is not None:
                blocks.append(current)
            current = {
                "type": "section",
                "title": line["text"],
                "lines": [],
            }
        elif current is None:
            preamble.append(line["text"])
        else:
            current["lines"].append(line["text"])

    if current is not None:
        blocks.append(current)

    # Only use the section model when it actually associates content with at
    # least one heading. Otherwise the paragraph fallback is safer.
    if not any(block["lines"] for block in blocks):
        return None

    if preamble:
        blocks.insert(0, {"type": "paragraph", "text": "\n".join(preamble)})
    return {"type": "document", "blocks": blocks}


def _menu_block(detections, image_width):
    lines = _line_groups(detections)
    price_count = sum(bool(_price_words(line["words"])) for line in lines)
    heading_count = sum(_is_heading(line["text"]) for line in lines)
    if price_count < 2 or heading_count < 1:
        return None

    midpoint = image_width / 2
    column_sets = [
        [word for word in detections if word["left"] + word["width"] / 2 < midpoint],
        [word for word in detections if word["left"] + word["width"] / 2 >= midpoint],
    ]
    if not all(len(column) >= 3 for column in column_sets):
        column_sets = [detections]

    sections = []
    for column in column_sets:
        column_lines = _line_groups(column)
        current = None
        index = 0
        while index < len(column_lines):
            line = column_lines[index]
            prices = _price_words(line["words"])
            if _is_heading(line["text"]) and not prices:
                # Presentation can style a heading without changing its
                # casing, punctuation, or Devanagari text.
                current = {"type": "menu_section", "title": line["text"], "items": []}
                sections.append(current)
                index += 1
                continue
            if not line["text"]:
                index += 1
                continue
            if current is None:
                current = {"type": "menu_section", "title": "Menu", "items": []}
                sections.append(current)

            price_text = " ".join(word["text"] for word in prices)
            name_words = [word for word in line["words"] if word not in prices]
            item = {
                "name": _text(name_words) or line["text"],
                "description": "",
                # Currency glyphs and price text are OCR facts. Keep them
                # exactly as detected in the source image.
                "price": price_text,
            }
            if index + 1 < len(column_lines):
                following = column_lines[index + 1]
                if (
                    not _price_words(following["words"])
                    and not _is_heading(following["text"])
                    and following["centerY"] - line["centerY"] <= max(70, line["words"][0]["height"] * 2.5)
                ):
                    item["description"] = following["text"]
                    index += 1
            current["items"].append(item)
            index += 1

    sections = [section for section in sections if section["items"]]
    return {"type": "document", "blocks": sections} if sections else None


def analyze_structure(image_shape, detections, grid, rendered_text):
    """Return a JSON-safe display model while keeping flat text as fallback."""
    image_height, image_width = image_shape[:2]
    if grid:
        table = _table_block(detections, grid)
        if table:
            return {"type": "document", "blocks": [table]}

    table = _aligned_table_block(detections)
    if table:
        return {"type": "document", "blocks": [table]}

    menu = _menu_block(detections, image_width)
    if menu:
        return menu

    columns = _columns(detections, image_width)
    if columns:
        return {
            "type": "document",
            "blocks": [{"type": "columns", "columns": columns}],
        }

    sections = _section_blocks(detections)
    if sections:
        return sections

    return {
        "type": "document",
        "blocks": [{"type": "paragraph", "text": rendered_text}],
    }


def render_structure(structure):
    """Create a readable flat representation for saving and speech."""
    if not isinstance(structure, dict):
        return ""
    rendered = []
    for block in structure.get("blocks", []):
        kind = block.get("type")
        if kind == "table":
            rendered.append(" | ".join(block.get("headers", [])))
            rendered.extend(" | ".join(row) for row in block.get("rows", []))
        elif kind == "menu_section":
            rendered.append(block.get("title", "Menu"))
            for item in block.get("items", []):
                line = item.get("name", "")
                if item.get("price"):
                    line = f"{line} — {item['price']}"
                rendered.append(line)
                if item.get("description"):
                    rendered.append(item["description"])
        elif kind == "columns":
            columns = block.get("columns", [])
            for column in columns:
                rendered.extend(column)
        elif kind == "section":
            if block.get("title"):
                rendered.append(block["title"])
            rendered.extend(
                line for line in block.get("lines", [])
                if line is not None
            )
        elif kind == "paragraph" and block.get("text"):
            rendered.append(block["text"])
    return "\n".join(line for line in rendered if line is not None).strip()