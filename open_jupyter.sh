#!/usr/bin/env bash
# Opens Jupyter Notebook with the sleap_env kernel (macOS / Linux)
# Rodrigo Garrido - Moita Lab - Champalimaud Foundation
#
# NOTE: best-effort adaptation of open_jupyter.ps1, not yet run on a real Mac or Linux machine.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME="sleap_env"
if [ -f "$SCRIPT_DIR/sleap_env_name.txt" ]; then
    saved="$(tr -d '[:space:]' < "$SCRIPT_DIR/sleap_env_name.txt")"
    [[ "$saved" =~ ^[A-Za-z0-9_-]+$ ]] && ENV_NAME="$saved"
fi

ENV_DIR=""
for c in "$(dirname "$(dirname "${CONDA_EXE:-/nonexistent/x}")")" "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/miniforge3" \
         "$HOME/mambaforge" "/opt/miniconda3" "/opt/anaconda3" "/opt/homebrew/Caskroom/miniconda/base" \
         "/usr/local/Caskroom/miniconda/base" "$HOME/.conda"; do
    if [ -x "$c/envs/$ENV_NAME/bin/jupyter" ]; then ENV_DIR="$c/envs/$ENV_NAME"; break; fi
done

if [ -z "$ENV_DIR" ]; then
    echo " ERROR: environment '$ENV_NAME' not found. Run setup_env.sh first."
    exit 1
fi

export PATH="$ENV_DIR/bin:$PATH"
export CONDA_PREFIX="$ENV_DIR" CONDA_DEFAULT_ENV="$ENV_NAME" PYTHONNOUSERSITE=1 PYTHONPATH=""

if ! "$ENV_DIR/bin/python" -c "import PIL, webcolors, nbformat, notebook.notebookapp" 2>/tmp/sleap_check.err; then
    cat /tmp/sleap_check.err
    echo ""
    echo " ERROR: the SLEAP environment is broken. Run setup_env.sh - it repairs it automatically."
    exit 1
fi

echo ""
echo " Opening Jupyter Notebook..."
echo " (your browser should open automatically in a moment)"
echo ""

cd "$SCRIPT_DIR"
"$ENV_DIR/bin/jupyter" notebook --notebook-dir="$SCRIPT_DIR"
