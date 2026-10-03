"""Local LAN backend, also usable through optional USB forwarding; no reloader."""
from pathlib import Path
import sys
import os
import logging
logging.basicConfig(level=logging.INFO)
root = Path(__file__).resolve().parents[3]
extra = root / 'hadeel-model-runtime'
if not extra.exists():
    extra = Path.home() / 'Documents' / 'Playground' / 'hadeel-model-runtime'
if extra.exists():
    sys.path.append(str(extra))
from app import app

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', '5000')), debug=False, use_reloader=False)
