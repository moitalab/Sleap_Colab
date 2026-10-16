#!/usr/bin/env bash
# SLEAP Pipeline - Environment Setup (macOS / Linux)
# Rodrigo Garrido - Moita Lab - Champalimaud Foundation
#
# Self-healing setup, same logic as setup_env.ps1 (Windows). Safe to re-run:
#   - never modifies conda's "base" environment (no mamba install)
#   - uses ONLY conda-forge / nvidia / sleap / anaconda.org (--override-channels),
#     so the Anaconda Terms-of-Service prompt never appears
#   - repairs a broken conda or falls back to Miniforge
#   - always re-applies the pip fixes and VALIDATES the environment; if it fails it
#     asks whether to recreate it (or to create one with another name)
#
# NOTE: NOT yet run on a real Mac/Linux machine (the Windows version is the tested one).
#   - No NVIDIA/CUDA on any Mac -> CPU-only environment on macOS.
#   - SLEAP 1.3.4 / TensorFlow 2.7 / Python 3.7 may lack native Apple Silicon builds.
#     If creation fails on an M1/M2/M3 Mac, re-run under Rosetta 2:
#         arch -x86_64 bash setup_env.sh
# Please report any issue so the script can be corrected.

DEFAULT_ENV="sleap_env"
KERNEL_NAME="sleap_env"
EXPECTED_SLEAP="1.3.4"
EXPECTED_TF="2.7.0"
FORGE_ROOT="$HOME/miniforge3"
MODEL_REPO="https://github.com/moitalab/Sleap_Colab.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME_FILE="$SCRIPT_DIR/sleap_env_name.txt"
OS="$(uname -s)"
ARCH="$(uname -m)"

CONDA_ROOT=""
SOLVER_ARGS=()
USING_FORGE=0

fail() { echo ""; echo " ERROR: $1"; exit 1; }

echo ""
echo "====================================================="
echo " SLEAP Pipeline - Environment Setup (macOS / Linux)"
echo " Rodrigo Garrido - Moita Lab - Champalimaud Foundation"
echo "====================================================="
echo ""
echo " This script installs everything automatically."
echo " It is safe to run again if something went wrong."
echo " First run takes about 15-25 minutes."
echo ""
echo " NVIDIA GPU (Linux only) : 2-10 minutes per video"
echo " CPU only (incl. all Macs): 1-4 HOURS per video"
echo " (the pipeline works either way)"
echo "====================================================="
echo ""
read -p "Press ENTER to continue..."

# ----------------------------------------------------------------
# helpers
# ----------------------------------------------------------------
conda_candidates() {
    [ -n "$CONDA_EXE" ] && dirname "$(dirname "$CONDA_EXE")"
    command -v conda >/dev/null 2>&1 && dirname "$(dirname "$(command -v conda)")"
    for c in "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/miniforge3" "$HOME/mambaforge" \
             "/opt/miniconda3" "/opt/anaconda3" "/opt/homebrew/Caskroom/miniconda/base" \
             "/usr/local/Caskroom/miniconda/base"; do
        echo "$c"
    done
}

find_conda_root() {
    while read -r c; do
        [ -n "$c" ] && [ -x "$c/bin/conda" ] && { echo "$c"; return 0; }
    done < <(conda_candidates)
    return 1
}

find_env_dir() {   # $1 = env name
    local n="$1" c
    while read -r c; do
        [ -n "$c" ] && [ -x "$c/envs/$n/bin/python" ] && { echo "$c/envs/$n"; return 0; }
    done < <(conda_candidates)
    [ -x "$HOME/.conda/envs/$n/bin/python" ] && { echo "$HOME/.conda/envs/$n"; return 0; }
    return 1
}

conda_healthy() {
    local out
    out="$("$CONDA_ROOT/bin/conda" --version 2>&1 && "$CONDA_ROOT/bin/conda" config --show solver 2>&1)" || return 1
    echo "$out" | grep -Eq 'Error while loading conda entry point|CondaValueError|Traceback|non-default solver' && return 1
    return 0
}

install_miniforge() {
    [ -x "$FORGE_ROOT/bin/conda" ] && return 0
    echo " Installing Miniforge (conda-forge only) to: $FORGE_ROOT"
    local url inst="/tmp/miniforge_setup.sh"
    if [ "$OS" = "Darwin" ]; then
        [ "$ARCH" = "arm64" ] && url="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-arm64.sh" \
                              || url="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-x86_64.sh"
    else
        url="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-$(uname -m).sh"
    fi
    curl -fsSL "$url" -o "$inst" || return 1
    bash "$inst" -b -p "$FORGE_ROOT"; rm -f "$inst"
    [ -x "$FORGE_ROOT/bin/conda" ]
}

switch_to_forge() {
    [ "$USING_FORGE" = "1" ] && return 1
    echo ""; echo " Falling back to a separate Miniforge install (your existing conda is left untouched)..."
    install_miniforge || return 1
    CONDA_ROOT="$FORGE_ROOT"; SOLVER_ARGS=(); USING_FORGE=1
    return 0
}

new_env() {   # $1 = name
    echo ""; echo " Creating environment '$1' (this can take 10-20 minutes)..."
    local pkgs=(python=3.7 "sleap=$EXPECTED_SLEAP" "tensorflow=$EXPECTED_TF" pandas=1.3.5 scipy=1.7.3 matplotlib=3.5.3 pillow jupyterlab ipykernel)
    local ch=(--override-channels -c conda-forge -c sleap -c anaconda)
    if [ "$OS" != "Darwin" ]; then
        ch=(--override-channels -c conda-forge -c nvidia -c sleap -c anaconda)
        pkgs+=(cudatoolkit=11.3.1 cudnn=8.2.1.32)
    fi
    "$CONDA_ROOT/bin/conda" create -y -n "$1" "${SOLVER_ARGS[@]}" "${ch[@]}" "${pkgs[@]}"
}

build_env() {   # default solver -> classic solver -> Miniforge
    new_env "$1" && return 0
    if [ ${#SOLVER_ARGS[@]} -eq 0 ]; then
        echo " Retrying with the classic solver..."
        SOLVER_ARGS=(--solver=classic)
        new_env "$1" && return 0
    fi
    if switch_to_forge; then new_env "$1" && return 0; fi
    return 1
}

repair_packages() {   # $1 = env dir
    echo " Applying compatibility fixes (webcolors, pillow, charset-normalizer)..."
    export PYTHONNOUSERSITE=1 PYTHONPATH=""
    "$1/bin/python" -m pip install -q --disable-pip-version-check "webcolors==1.11.1" "charset-normalizer<3"
    "$1/bin/python" -m pip install -q --disable-pip-version-check --force-reinstall "pillow<10"
}

VALIDATE_OUT=""; VALIDATE_GPU=0
validate_env() {   # $1 = env dir
    export PYTHONNOUSERSITE=1 PYTHONPATH=""
    VALIDATE_OUT="$("$1/bin/python" -c "import PIL, webcolors, jsonschema, nbformat; import notebook.notebookapp; import tensorflow as tf; import sleap; print('SLEAP_OK', sleap.__version__, tf.__version__, len(tf.config.list_physical_devices('GPU')))" 2>&1)"
    local line; line="$(echo "$VALIDATE_OUT" | grep 'SLEAP_OK' | tail -1)"
    [ -z "$line" ] && { VALIDATE_REASON="imports failed"; return 1; }
    set -- $line
    if [ "$2" != "$EXPECTED_SLEAP" ] || [ "$3" != "$EXPECTED_TF" ]; then
        VALIDATE_REASON="wrong versions (sleap $2, tensorflow $3; expected $EXPECTED_SLEAP / $EXPECTED_TF)"; return 1
    fi
    VALIDATE_GPU="$4"; return 0
}

ask_yes_no() {
    local a
    while true; do
        read -p "$1 [Y/N] " a
        case "$(echo "$a" | tr 'A-Z' 'a-z')" in y|yes|s|sim) return 0;; n|no|nao) return 1;; esac
    done
}

ask_new_name() {
    local n
    while true; do
        read -p " New environment name (letters, numbers, - or _): " n
        [[ "$n" =~ ^[A-Za-z0-9_-]+$ ]] || { echo " Invalid name." >&2; continue; }
        find_env_dir "$n" >/dev/null && { echo " '$n' already exists. Choose another." >&2; continue; }
        echo "$n"; return
    done
}

# ----------------------------------------------------------------
# 0. conda
# ----------------------------------------------------------------
echo ""; echo "[0/4] Checking for conda..."
CONDA_ROOT="$(find_conda_root)"
if [ -z "$CONDA_ROOT" ]; then
    echo " Conda not found. Installing Miniconda (~90MB)..."
    if [ "$OS" = "Darwin" ]; then
        [ "$ARCH" = "arm64" ] && URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh" \
                              || URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh"
    else
        URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    fi
    if curl -fsSL "$URL" -o /tmp/miniconda_setup.sh && bash /tmp/miniconda_setup.sh -b -p "$HOME/miniconda3" \
        && [ -x "$HOME/miniconda3/bin/conda" ]; then
        CONDA_ROOT="$HOME/miniconda3"; echo " OK - Miniconda installed."
    else
        switch_to_forge || fail "Could not install conda. Check your internet connection and try again."
    fi
    rm -f /tmp/miniconda_setup.sh
fi
[ "$CONDA_ROOT" = "$FORGE_ROOT" ] && USING_FORGE=1
echo " Conda: $CONDA_ROOT"

# ----------------------------------------------------------------
# 1. conda health
# ----------------------------------------------------------------
echo ""; echo "[1/4] Checking that conda works..."
if conda_healthy; then
    echo " OK"
else
    echo " conda looks broken (solver plugin mismatch). Trying to repair it..."
    "$CONDA_ROOT/bin/conda" update -y -n base --solver=classic --override-channels -c conda-forge \
        conda conda-libmamba-solver libmambapy
    if conda_healthy; then
        echo " OK - conda repaired."
    else
        echo " Could not repair conda."
        switch_to_forge || fail "conda is unusable and Miniforge could not be installed."
    fi
fi

# ----------------------------------------------------------------
# 2. environment
# ----------------------------------------------------------------
echo ""; echo "[2/4] Preparing the SLEAP environment..."
ENV_NAME="$DEFAULT_ENV"
if [ -f "$ENV_NAME_FILE" ]; then
    saved="$(tr -d '[:space:]' < "$ENV_NAME_FILE")"
    [[ "$saved" =~ ^[A-Za-z0-9_-]+$ ]] && ENV_NAME="$saved"
fi

ENV_DIR="$(find_env_dir "$ENV_NAME")"
if [ -z "$ENV_DIR" ]; then
    build_env "$ENV_NAME" || fail "Failed to create the environment. Check your internet connection and try again."
    ENV_DIR="$(find_env_dir "$ENV_NAME")" || fail "Environment '$ENV_NAME' was created but could not be located."
else
    echo " Environment '$ENV_NAME' found: $ENV_DIR"
fi

repair_packages "$ENV_DIR"
echo " Validating environment (imports sleap / tensorflow / jupyter - can take a minute)..."
if ! validate_env "$ENV_DIR"; then
    echo ""; echo " Environment '$ENV_NAME' is NOT working: $VALIDATE_REASON"
    echo " --- last output ---"; echo "$VALIDATE_OUT" | tail -8; echo " -------------------"; echo ""
    if ask_yes_no " Delete and recreate '$ENV_NAME'?"; then
        "$CONDA_ROOT/bin/conda" env remove -y -n "$ENV_NAME" >/dev/null 2>&1
        [ -d "$ENV_DIR" ] && rm -rf "$ENV_DIR"
    else
        ENV_NAME="$(ask_new_name)"
    fi
    build_env "$ENV_NAME" || fail "Failed to create environment '$ENV_NAME'."
    ENV_DIR="$(find_env_dir "$ENV_NAME")" || fail "Environment '$ENV_NAME' was created but could not be located."
    repair_packages "$ENV_DIR"
    validate_env "$ENV_DIR" || { echo "$VALIDATE_OUT"; fail "Environment '$ENV_NAME' still fails validation ($VALIDATE_REASON). Send the text above to Rodrigo."; }
fi
echo "$ENV_NAME" > "$ENV_NAME_FILE"
echo " OK - environment '$ENV_NAME' works (SLEAP $EXPECTED_SLEAP, TensorFlow $EXPECTED_TF)."
if [ "${VALIDATE_GPU:-0}" -gt 0 ]; then echo " GPU detected: $VALIDATE_GPU device(s) - fast mode."; else echo " No GPU detected - CPU mode (slow but works)."; fi

# ----------------------------------------------------------------
# 3. kernel
# ----------------------------------------------------------------
echo ""; echo "[3/4] Registering the Jupyter kernel..."
if PYTHONNOUSERSITE=1 "$ENV_DIR/bin/python" -m ipykernel install --user --name "$KERNEL_NAME" --display-name "Python (sleap_env)"; then
    echo ' OK - Kernel "Python (sleap_env)" registered.'
else
    echo " WARNING: Kernel registration failed. Run setup_env.sh again."
fi

# ----------------------------------------------------------------
# 4. model
# ----------------------------------------------------------------
echo ""; echo "[4/4] Downloading the SLEAP model (Moita Lab)..."
MODEL_DIR="$SCRIPT_DIR/Sleap_Model"
model_ok() { [ -f "$MODEL_DIR/best_model.h5" ] && [ "$(wc -c < "$MODEL_DIR/best_model.h5")" -gt 1048576 ]; }

if [ -d "$MODEL_DIR/.git" ]; then
    echo " Model already exists. Checking for updates..."
    (cd "$MODEL_DIR" && git pull >/dev/null 2>&1) || true
elif [ ! -d "$MODEL_DIR" ] || [ -z "$(ls -A "$MODEL_DIR" 2>/dev/null)" ]; then
    if ! { command -v git >/dev/null 2>&1 && git clone "$MODEL_REPO" "$MODEL_DIR"; }; then
        echo " git not found or failed - downloading ZIP instead..."
        if curl -fsSL "https://github.com/moitalab/Sleap_Colab/archive/refs/heads/main.zip" -o /tmp/sleap_model.zip; then
            unzip -q /tmp/sleap_model.zip -d "$SCRIPT_DIR"
            [ -d "$SCRIPT_DIR/Sleap_Colab-main" ] && mv "$SCRIPT_DIR/Sleap_Colab-main" "$MODEL_DIR"
            rm -f /tmp/sleap_model.zip
        fi
    fi
fi

# best_model.h5 is stored with Git LFS: without git-lfs (or via ZIP) only a tiny pointer file arrives.
if ! model_ok && [ -d "$MODEL_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    echo " Fetching model weights via Git LFS..."
    (cd "$MODEL_DIR" && git lfs install >/dev/null 2>&1; git lfs pull >/dev/null 2>&1) || true
fi
if ! model_ok; then
    echo " Downloading model weights directly from GitHub..."
    mkdir -p "$MODEL_DIR"
    for f in best_model.h5 training_config.json; do
        curl -fsSL "https://github.com/moitalab/Sleap_Colab/raw/main/$f" -o "$MODEL_DIR/$f" || true
    done
fi
if model_ok; then
    echo " OK - model ready."
else
    echo " WARNING: best_model.h5 is missing or incomplete."
    echo "          Download it manually: https://github.com/moitalab/Sleap_Colab"
    echo "          and place the folder, named \"Sleap_Model\", next to this script."
fi

echo ""
echo "====================================================="
echo " Setup complete"
echo "====================================================="
echo ""
echo " To get started:"
echo " 1. Run:  bash open_jupyter.sh"
echo " 2. Open SLEAP_Local.ipynb"
echo ' 3. Select the "Python (sleap_env)" kernel'
echo " 4. Fill in the configuration cell and run the 3 steps"
echo ""
echo "====================================================="
