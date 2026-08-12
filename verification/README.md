# Falcon Verification

This repository contains cocotb-based verification tests for Falcon hardware components.
The verification suite covers:
- `hash_to_point` — verifies the `HashToPoint` hardware block against a Python reference model.
- `keccak` — verifies the `Keccak` permutation core against a Python reference implementation.
- `shake256` — verifies the `Shake256` wrapper using Python's `hashlib.shake_256`.

## Prerequisites

- Python 3.13 or newer.
- `iverilog` / `vvp` installed for Icarus Verilog simulation, or another supported cocotb simulator.
- `cocotb` and `cocotb-tools` installed in the Python environment.
- Verilog design sources available at `../Verilog/ComputeEngine` and `../Verilog/falcon_pkg.sv` relative to this verification folder.

Create a virtual environment and install the dependencies
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Setup

Activate the local verification environment:

```bash
cd /Users/henderson/Documents/Research/FALCON/Falcon-Verification/verification
source venv/bin/activate
```

If you need to install dependencies manually:

```bash
python -m pip install cocotb cocotb-tools pytest
```

## Running Tests

Each module has its own cocotb test driver. From the `verification` choose the desire module to verify. For instance, to verify the shake256 module,

```bash
cd shake256/tests
make
```

To obtain the `.fst` file, add WAVES=1.

```bash
make WAVES=1
```

The `.vvp` and `.fst` files can be find under `sim_build`. For `shake256`, after execution of `make`, the `.vvp` and `.fst` files are under `shake256/tests/sim_build`


## Module Details

- `hash_to_point`
  - Uses the Python reference model in `hash_to_point/model/hash_to_point.py`.
  - Compares hardware `HashToPoint` outputs against the reference implementation.

- `keccak`
  - Uses the Python model `keccak/model/keccak_model.py`.
  - Verifies the `Keccak` core for both zero input and random state vectors.

- `shake256`
  - Uses Python's `hashlib.shake_256` to verify the SHAKE output.
  - Exercises the `Shake256` wrapper and its internal `Keccak` instantiation.

## Notes

- The tests expect the Verilog sources to be present outside the verification folder in a `Verilog` sibling tree.
- If running tests from a different path, ensure the relative source paths in each module's `tests/Makefile` or test runner are still valid.
- If you are not using the bundled `verilog_venv`, activate your own Python environment and install the same dependencies.
