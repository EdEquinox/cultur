from __future__ import annotations

import sys
from pathlib import Path


YAMTRACK_API_ROOT = Path(__file__).resolve().parents[1]

if str(YAMTRACK_API_ROOT) not in sys.path:
    sys.path.insert(0, str(YAMTRACK_API_ROOT))
