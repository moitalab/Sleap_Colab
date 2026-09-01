#!/usr/bin/env bash
# Opens Jupyter Notebook with the sleap_env kernel (macOS / Linux)
# Rodrigo Garrido - Moita Lab - Champalimaud Foundation
#
# NOTE: best-effort adaptation of abrir_jupyter.bat / abrir_jupyter.ps1,
# not yet run on a real Mac or Linux machine. Unlike on Windows, no PATH
# workaround is needed here for native libraries - `conda run` is enough.

CONDA_ROOT=""
for candidate in "$HOME/miniconda3" "$HOME/anaconda3" "/opt/miniconda3" "/opt/anaconda3"; do
    if [ -x "$candidate/bin/conda" ]; then
        CONDA_ROOT="$candidate"
        break
    fi
done

if [ -z "$CONDA_ROOT" ]; then
    echo " ERROR: conda not found. Run setup_env.sh first."
    exit 1
fi

if [ ! -x "$CONDA_ROOT/envs/sleap_env/bin/jupyter" ]; then
    echo " ERROR: sleap_env environment not found. Run setup_env.sh first."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo " Opening Jupyter Notebook..."
echo " (your browser should open automatically in a moment)"
echo ""

cd "$SCRIPT_DIR"
"$CONDA_ROOT/bin/conda" run -n sleap_env jupyter notebook --notebook-dir="$SCRIPT_DIR"
