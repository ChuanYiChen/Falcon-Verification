from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_model_dir = Path(__file__).resolve().parents[2] / "polymul" / "model"
if str(_model_dir) not in sys.path:
    sys.path.insert(0, str(_model_dir))

_model_path = _model_dir / "ntt.py"
_spec = importlib.util.spec_from_file_location("ntt_reference", _model_path)
if _spec is None or _spec.loader is None:
    raise ImportError(f"Unable to load reference model from {_model_path}")
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)

for _name in dir(_module):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_module, _name)

q = _module.q
