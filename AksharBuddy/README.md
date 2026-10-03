# AksharBuddy local model edition
Read ../START_HERE.md first. This Flutter/Flask app supports local reading, OCR review and local IndicBART inference. Model quality has NOT passed: see ../MODEL_ASSESSMENT.md.

## Layout
- aksharally_ui: Flutter app (display name AksharBuddy).
- backend: Flask API, OCR and local-model adapter.
- backend/models/aksharbuddy-indicbart: supplied trained checkpoint.

## Local source commands (PowerShell, no project Git needed)
From backend, with the configured Python environment: `python -m unittest discover -s tests -v` and `python run_local.py`.
From aksharally_ui: `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug`.
The app defaults to http://127.0.0.1:5000; the parent launcher configures ADB reverse for a connected Android phone. Flutter uses its own SDK checks internally.

For model inference on this prepared laptop, run_local.py adds the sibling hadeel-model-runtime dependency directory. Setup AksharBuddy.ps1 installs dependencies into backend/.venv for another machine. Tesseract and its language data are separate native dependencies. This delivery APK is a debug/test build, not a signed Play Store release.

## Authentication and storage
Try without an account opens supported local features. Firebase configuration from the supplied app is retained; live registration/login/recovery are not accepted as tested in this delivery. The backend has no private Firebase admin credential. Local SharedPreferences data is shared by accounts using this app installation, is not encrypted document storage, and can be removed by clearing app data or uninstalling. No cloud backup is implemented.
