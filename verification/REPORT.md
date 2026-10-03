# LAN and OCR repair verification — 2 October 2026

## Outcome

Changes are isolated in `AksharBuddy-LAN-repair`. The existing `hadeel_major project` testing folder was used only as a read-only baseline. No project Git or Git Bash operations were used.

Implemented:

- Flask binds `0.0.0.0:5000`; normal launcher starts without ADB or a phone. USB reverse is an explicit `-Usb` fallback.
- Saved LAN URL and health check in app Settings, with actionable unreachable messages. APK default is the observed laptop Wi-Fi address, `192.168.29.68`.
- Android main manifest permits local HTTP. A separate firewall helper permits TCP 5000 only for LocalSubnet/Private profile; it was not executed.
- Printed documents use Tesseract first. EasyOCR is retained as a cached, locked fallback with two CPU threads and no runtime downloads. The old code already cached the reader: reloading per request was **not** the measured cause.
- EXIF orientation, decoded-image resizing to 2400px, per-stage timings, bounded recognition calls, and no denoising on normal successful requests.
- Asynchronous extraction jobs, bounded single-worker queue, polling progress with page numbers, explicit failures, cancellation between processing stages, and result expiry. PDFs use selectable text first; scanned pages avoid a PNG encode/decode round-trip.
- Keep my words uses only extraction/formatting; typed text in this mode stays entirely on the phone.
- Local model load and generation are measured separately. Its existing cache is retained. No replacement model or cloud API was introduced.
- Conservative numeric/date/time/unit, negation, Latin-name and script/language checks reject unsafe or uncertain model outputs. These are not comprehensive semantic verification, multilingual named-entity recognition, or a statistically validated language detector.
- TTS selects installed offline voices and tries installed engines in the same language; availability diagnostics are logged and cached on-device. Missing voices lead to installation guidance, not an English language substitution. Settings can open Android voice settings.
- Saved Words entries reopen their cached meaning/example and Hear this word button. Home shows one last-opened Continue reading card, persisted across restarts.

## Before / after timings

Same synthetic fixtures, same laptop; actual endpoint calls, not mocked OCR. Times are single runs, not statistical service-level guarantees. Flask test-client measurements exclude phone/network transfer.

| Case | Before | After |
|---|---:|---:|
| Tiny English image, first OCR request | 39.723 s | 1.714 s |
| Tiny English image, warm repeat | 4.841 s | 0.234 s |
| Normal 1400×1900 scanned page | 89.977 s | 1.044 s |
| Digital PDF, 3 native-text pages | 0.123 s | 0.067 s |
| Scanned PDF, 3 pages / 7.98 MB | 274.264 s | 4.318 s |
| Keep my words, normal scanned page | 89.977 s | 1.044 s |
| AI mode, short English text, first request | 42.548 s | 12.774 s |
| AI mode, same short English text, warm repeat | 0.733 s | 0.724 s |

OCR baseline tiny cold request: EasyOCR initialization **33.621 s**, recognition **5.534 s**. Normal page recognition alone was **89.748 s**. After: normal-page decode/resize **0.083 s**, preprocessing **0.124 s**, recognition **0.780 s**. The original engine also misread Latin `12` as Devanagari digits on these English fixtures; the new path preserved the printed digits.

AI startup is strongly affected by filesystem cache and available RAM: load/import time measured **39.912 s** in the before run and **9.847 s** in the after run; a later quality run loaded in **31.324 s**. These are **not evidence of a model-loading optimization**. Both versions already reuse the same loaded model. Warm English/Hindi/Marathi short-text after calls took **0.724 / 0.831 / 0.979 s**. In AI image mode, OCR plus generation are separate stages; review/edit time is user-controlled and is not included.

Actual HTTP smoke test bound all interfaces on a temporary unused port, called the laptop's LAN IPv4, uploaded the scanned PDF, polled pages 1–3 and checked the result. Upload/enqueue: **0.233 s**; total: **5.218 s**. This uses the laptop network stack, **not a phone-to-router Wi-Fi measurement**. Port 5000 and the existing user backend were not disturbed.

## Checks completed

- Backend: **23 tests passed** (including no-model extraction, short native PDF bypass, numeric/date/unit/negation/name rejection, Hindi↔Marathi rejection, and existing layout tests).
- Flutter: **38 tests passed**, including LAN polling/health, original text, reading-position restore, simulated device speech, offline saved-word data, last-opened reading and large-text layouts.
- Flutter analyzer: **No issues found**.
- Android debug APK built successfully; APK signature verifies with v2 signing. Manifest confirms INTERNET, cleartext HTTP and TTS-service visibility.
- Reviewed rendered Settings and Words screenshots; golden screenshots regenerated for intentional UI changes, then the suite passed against them. Golden updates are rendering evidence, not physical-device UX validation.
- Launcher PowerShell parses; `-CheckOnly` finds Python and prints the LAN address without starting a server.
- 21 OCR regression cases: clean English/Hindi/Marathi and their tilted samples exact; tested image columns/table and digital/scanned-column PDFs exact. Blank page correctly rejected. Heavy Marathi blur: **22.22% word error**. One real handwritten English sample: **33.33% word error**. Those difficult cases remain unreliable; this small set does not establish general handwriting accuracy.

## Still unfinished

1. **Model simplification quality.** The supplied checkpoint and earlier small pilot copied held-out passages. This repair does not retrain/promote a checkpoint. See `model-quality.json` for the fresh nine-passage challenge results. Unchanged text is never a quality pass. A larger, reviewed training/evaluation corpus and successful unseen-language tests are still required.
2. **Physical phone validation:** app install, cable-unplugged LAN/hotspot test, real TTS voice availability/audio, camera capture, interruption/resume and offline voice checks. Mocked speech-interface tests cannot prove audible output.
3. **Live authentication:** private backend credentials are not packaged and no live authentication check was performed. Guest/local features remain.
4. Public deployment/store release: this is a local development repair APK/server, not an authenticated internet service or release-signed store build.

Evidence: `before-timings.json`, `after-timings.json`, `ocr-regression.json`, `model-before.json`, `model-after.json`, `model-quality.json`, `lan-smoke.json`, `backend-tests.txt`, `flutter-tests.txt`, `flutter-analysis.txt`, `apk-build.txt`.
