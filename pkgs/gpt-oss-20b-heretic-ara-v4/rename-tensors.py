"""Rename p-e-w/gpt-oss-20b-heretic-ara-v4 tensors: collapse the doubled
`_blocks_blocks` / `_blocks_scales` suffix back to the canonical `_blocks`
/ `_scales` naming the llama.cpp gpt-oss converter expects.

The ara-v4 weights save MoE block tensors with an extra `_blocks` infix
(e.g. `gate_up_proj_blocks_scales`), which makes the converter's substring
match treat the 3D scales tensor as a 4D blocks tensor and crash with
`IndexError: too many indices for tensor of dimension 3`.
"""

import sys
from pathlib import Path

from safetensors.torch import load_file, save_file

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

sd = load_file(str(src))
renamed = {
    k.replace("_blocks_blocks", "_blocks").replace("_blocks_scales", "_scales"): v
    for k, v in sd.items()
}
save_file(renamed, str(dst))
