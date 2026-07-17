#!/usr/bin/env bash
# SLEAP Pipeline - Environment Setup (macOS / Linux)
# Rodrigo Garrido - Moita Lab - Champalimaud Foundation
#
# NOTE: this is a best-effort adaptation of setup_env.bat / setup_env.ps1
# (the original, tested Windows setup script). It has NOT been run on a
# real Mac or Linux machine. In particular:
#   - There is no NVIDIA/CUDA support on any Mac, so this script always
#     installs a CPU-only environment on macOS.
#   - SLEAP 1.3.4 / TensorFlow 2.7 / Python 3.7 are old packages and may
#     not have native Apple Silicon (arm64) builds on conda-forge. If the
#     environment creation fails on an M1/M2/M3 Mac, try re-running this
#     script under Rosetta 2:  arch -x86_64 bash setup_env.sh
#   - On Linux, GPU acceleration requires an NVIDIA GPU with up-to-date
#     drivers; without one, the environment still installs but inference
#     runs on CPU (slower, see the notebooks for the expected impact).
# If you hit issues not covered here, please report them back so this
# script can be corrected for real.

set -e

echo ""
echo "====================================================="
echo " SLEAP Pipeline - Environment Setup (macOS / Linux)"
echo " Rodrigo Garrido - Moita Lab - Champalimaud Foundation"
echo "====================================================="
echo ""
echo " This script installs everything automatically."
echo " Nothing needs to be installed manually beforehand."
echo " First run takes about 15-25 minutes."
echo ""
echo "====================================================="
echo " NOTE: GPU acceleration"
echo "====================================================="
echo ""
echo " NVIDIA GPU (Linux only) : 2-10 minutes per video"
echo " CPU only (incl. all Macs): 1-4 HOURS per video"
echo ""
echo " (the pipeline works either way)"
echo "====================================================="
echo ""
read -p "Press ENTER to continue..."

OS="$(uname -s)"
ARCH="$(uname -m)"

# ================================================================
# 0. FIND OR INSTALL CONDA
# ================================================================
echo ""
echo "[0/4] Checking for conda..."

CONDA_ROOT=""
for candidate in "$HOME/miniconda3" "$HOME/anaconda3" "/opt/miniconda3" "/opt/anaconda3"; do
    if [ -x "$candidate/bin/conda" ]; then
        CONDA_ROOT="$candidate"
        break
    fi
done

if [ -z "$CONDA_ROOT" ]; then
    echo " Conda not found. Installing Miniconda..."
    echo " (downloading ~90MB - please wait)"
    echo ""

    CONDA_ROOT="$HOME/miniconda3"
    INSTALLER="/tmp/miniconda_setup.sh"

    if [ "$OS" = "Darwin" ]; then
        if [ "$ARCH" = "arm64" ]; then
            URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh"
        else
            URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh"
        fi
    else
        URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    fi

    if ! curl -fsSL "$URL" -o "$INSTALLER"; then
        echo ""
        echo " ERROR: Could not download Miniconda."
        echo " Check your internet connection and try again."
        exit 1
    fi

    bash "$INSTALLER" -b -p "$CONDA_ROOT"
    rm -f "$INSTALLER"

    if [ ! -x "$CONDA_ROOT/bin/conda" ]; then
        echo ""
        echo " ERROR: Miniconda installation failed."
        exit 1
    fi
    echo " OK - Miniconda installed."
fi

CONDA_EXE="$CONDA_ROOT/bin/conda"
echo " OK - Conda: $CONDA_ROOT"

# ================================================================
# 1. INSTALL MAMBA
# ================================================================
echo ""
echo "[1/4] Installing mamba (this can take a few minutes)..."

"$CONDA_EXE" install -y -n base -c conda-forge mamba

SOLVER="$CONDA_EXE"
if [ -x "$CONDA_ROOT/bin/mamba" ]; then
    SOLVER="$CONDA_ROOT/bin/mamba"
    echo " OK - mamba installed."
else
    echo " WARNING: mamba not found - using conda directly."
fi

# ================================================================
# 2. CREATE THE sleap_env ENVIRONMENT
# ================================================================
echo ""
echo "[2/4] Creating the sleap_env environment..."
echo "      (this can take 10-20 minutes)"
echo ""

if "$CONDA_EXE" env list 2>/dev/null | grep -q "sleap_env"; then
    echo " sleap_env already exists - skipping."
else
    if [ "$OS" = "Darwin" ]; then
        # No NVIDIA/CUDA support on macOS - CPU-only environment.
        "$SOLVER" create -y -n sleap_env \
            -c conda-forge -c sleap -c anaconda \
            python=3.7 \
            sleap=1.3.4 \
            tensorflow=2.7.0 \
            pandas=1.3.5 \
            scipy=1.7.3 \
            matplotlib=3.5.3 \
            pillow \
            jupyterlab \
            ipykernel
    else
        "$SOLVER" create -y -n sleap_env \
            -c conda-forge -c nvidia -c sleap -c anaconda \
            python=3.7 \
            sleap=1.3.4 \
            tensorflow=2.7.0 \
            cudatoolkit=11.3.1 \
            cudnn=8.2.1.32 \
            pandas=1.3.5 \
            scipy=1.7.3 \
            matplotlib=3.5.3 \
            pillow \
            jupyterlab \
            ipykernel
    fi

    echo ""
    echo " OK - sleap_env environment created."

    # Fix webcolors (newer versions use syntax incompatible with Python 3.7)
    "$CONDA_EXE" run -n sleap_env pip install -q "webcolors==1.11.1"

    # Pin Pillow (newer Pillow removed APIs that SLEAP 1.3.4 relies on)
    "$CONDA_EXE" run -n sleap_env pip install -q --force-reinstall "pillow<10"

    # Fix requests/charset-normalizer warning
    "$CONDA_EXE" run -n sleap_env pip install -q "charset-normalizer<3"
fi

# ================================================================
# 3. REGISTER THE JUPYTER KERNEL
# ================================================================
echo ""
echo "[3/4] Registering the Jupyter kernel..."

if "$CONDA_EXE" run -n sleap_env python -m ipykernel install --user --name sleap_env --display-name "Python (sleap_env)"; then
    echo ' OK - Kernel "Python (sleap_env)" registered.'
else
    echo " WARNING: Kernel registration failed. Try manually afterwards:"
    echo "          conda activate sleap_env"
    echo "          python -m ipykernel install --user --name sleap_env"
fi

# ================================================================
# 4. DOWNLOAD THE MODEL FROM GITHUB
# ================================================================
echo ""
echo "[4/4] Downloading the SLEAP model (Moita Lab)..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "$SCRIPT_DIR/Sleap_Model/.git" ]; then
    echo " Model already exists. Checking for updates..."
    (cd "$SCRIPT_DIR/Sleap_Model" && git pull >/dev/null 2>&1) || true
    echo " OK"
elif command -v git >/dev/null 2>&1; then
    git clone https://github.com/moitalab/Sleap_Colab.git "$SCRIPT_DIR/Sleap_Model"
else
    echo " git not found - downloading ZIP instead..."
    MODEL_ZIP="/tmp/sleap_model.zip"
    if curl -fsSL "https://github.com/moitalab/Sleap_Colab/archive/refs/heads/main.zip" -o "$MODEL_ZIP"; then
        unzip -q "$MODEL_ZIP" -d "$SCRIPT_DIR"
        [ -d "$SCRIPT_DIR/Sleap_Colab-main" ] && mv "$SCRIPT_DIR/Sleap_Colab-main" "$SCRIPT_DIR/Sleap_Model"
        rm -f "$MODEL_ZIP"
        echo " OK - Model extracted."
    else
        echo " WARNING: Could not download the model."
        echo "          Download it manually: https://github.com/moitalab/Sleap_Colab"
        echo "          and place the folder, named \"Sleap_Model\", next to this script."
    fi
fi

echo ""
echo "====================================================="
echo " Setup complete!"
echo "====================================================="
echo ""
echo " To get started:"
echo ""
echo " 1. Open a new terminal and run:"
echo "       $CONDA_EXE run -n sleap_env jupyter lab"
echo ""
echo " 2. Open SLEAP_Local.ipynb"
echo ' 3. Select the "Python (sleap_env)" kernel'
echo " 4. Fill in the configuration cell and run the 3 steps"
echo ""
echo "====================================================="
