# Colab_SLEAP: Automated Pipeline & Pre-trained Model

This repository provides an end-to-end solution for animal pose estimation using **SLEAP (Social LEAP Estimates Animal Poses)**. It features automated Google Colab and local (Windows / macOS / Linux) workflows designed for high-throughput batch processing, paired with a pre-trained UNet model optimized for single-animal tracking.

It combines **Bonsai** (centroid tracking) with **SLEAP.ai** (deep-learning pose estimation): each video crop is tracked with SLEAP to get keypoint positions relative to the fly's centroid, then combined with the Bonsai centroid CSV to produce a single pose CSV with positions normalized (0–1) to the arena.

---

## The Notebooks

All four notebooks run the exact same pipeline (SLEAP inference + Bonsai post-processing) and are specifically tailored to recognize and navigate the **Moita Lab** data structure automatically. They only differ in where they run and where the trained model comes from.

| Notebook | Environment | Model source |
| :--- | :--- | :--- |
| `Colab_SLEAP_AI_GITHUB.ipynb` | Google Colab (Tesla T4 GPU) | Clones the trained model straight from the [moitalab/Sleap_Colab](https://github.com/moitalab/Sleap_Colab) GitHub repository. |
| `Colab_SLEAP_AI_DRIVE.ipynb` | Google Colab (Tesla T4 GPU) | Loads the trained model from a folder in your own Google Drive, picked with a file chooser — no GitHub access needed. |
| `SLEAP_Local.ipynb` | Local (Windows / macOS / Linux) | Reads the model from the `Sleap_Model/` folder next to the notebook (populated by `setup_env` via a GitHub clone). |
| `SLEAP_Local_Pasta.ipynb` | Local (Windows / macOS / Linux) | Reads the model from any local folder you point it at — no GitHub dependency at all. |

The Colab notebooks use `condacolab`, which helps bypass Colab's default Python limitations so SLEAP can run inside an environment with the necessary drivers.

### Key Features:
* **Automated Hierarchy Management:** Point the notebook at an "Experiment" root folder, and it automatically locates `/PostProcessing/CropRaw` for videos and `/PostProcessing/Arenas` for normalization data.
* **Dynamic Normalization:** Instead of fixed scaling, the pipeline reads the `.png` arena files to ensure coordinates are perfectly normalized ($0.0$ to $1.0$) based on the specific resolution of each session.
* **Environment Integrity:** Builds a clean SLEAP v1.3.4 environment with optimized TensorFlow and CUDA drivers — via `condacolab` + `mamba` on Colab, or via the setup scripts below on Windows/macOS/Linux.

---

## How to Use — Google Colab

1. **Define Paths:** Run the initialization cell to mount your Google Drive and select your **Experiment Root Folder** (and, in the Drive notebook, the **Model Folder** too — it must contain `best_model.h5` and `training_config.json`). The script verifies the internal folder structure and creates a `Pose` subfolder for the results.
2. **Prepare the Environment:** Run the setup cells to build the Conda environment and dependencies via `condacolab` + `mamba`. **The kernel restarts after this step** — re-run the *Define Paths* cell before running the final pipeline cell.
3. **Run SLEAP:** Execute the final tracking cell. The script processes all `.avi` files in `CropRaw` and outputs both `.slp` (SLEAP) and `_pose.csv` (Bonsai-ready) files.

## How to Use — Local (Windows / macOS / Linux)

1. **Setup (once per machine):** Run `setup_env.bat` (Windows) or `setup_env.sh` (macOS/Linux). It installs Miniconda if needed, creates the `sleap_env` conda environment (SLEAP 1.3.4, TensorFlow 2.7, Python 3.7 — plus CUDA 11.3 on Windows/Linux with an NVIDIA GPU), registers the `Python (sleap_env)` Jupyter kernel, and downloads the trained model into `Sleap_Model/`.
2. **Launch Jupyter:** Run `abrir_jupyter.bat` (Windows) or `abrir_jupyter.sh` (macOS/Linux). This opens Jupyter Notebook in the project folder with the `sleap_env` kernel ready to use.
3. **Run the pipeline:** Open `SLEAP_Local.ipynb` or `SLEAP_Local_Pasta.ipynb`, select the `Python (sleap_env)` kernel, fill in the paths in the **Configuration** cell, then run **Configuration → Validation → Pipeline** in order.

A GPU is optional but strongly recommended — CPU-only inference can take 1–4 hours per video, vs. 2–10 minutes with an NVIDIA GPU. **No Mac has NVIDIA GPU support**, so macOS always runs CPU-only; if that's too slow, use one of the Google Colab notebooks instead (free GPU, runs in the browser).

### Setup scripts (local only)
* `setup_env.bat` / `setup_env.sh` — one-time, fully automatic setup (installs Miniconda + mamba, creates the `sleap_env` environment, registers the Jupyter kernel, downloads the model).
* `abrir_jupyter.bat` / `abrir_jupyter.sh` — launches Jupyter Notebook with the `sleap_env` environment ready to use.

> **Platform support note:** `setup_env.bat` / `abrir_jupyter.bat` (Windows) are tested and confirmed working. `setup_env.sh` / `abrir_jupyter.sh` (macOS/Linux) are a best-effort adaptation that has **not** been run on a real Mac or Linux machine yet — Apple Silicon Macs in particular may need extra steps (see the comments at the top of `setup_env.sh`). Please report any issues so the scripts can be fixed.

---

## Model Specifications

The provided model is a high-accuracy **Single Instance** tracker utilizing a specialized UNet architecture.

| Feature | Details |
| :--- | :--- |
| **Architecture** | UNet (16 filters, 1 stack) |
| **Input Resolution** | 128 x 128 pixels |
| **Training Set** | ~3,283 labeled frames |
| **Context** | Optimized for complex "dirt/substrate" backgrounds |
| **Data Augmentation** | Rotation ($\pm 180^\circ$), Scaling ($0.4x$–$1.6x$) |

### Skeleton (Keypoints)
The model tracks **8 nodes**, which are automatically mapped to standard lab naming conventions during export:

| Node | Export Name |
| :--- | :--- |
| **H** | Head |
| **Trx** | Thorax |
| **Abd** | Abdomen |
| **Lw** | LeftWing |
| **Rw** | RightWing |
| **L** | Left |
| **R** | Right |
| **T** | Top |

---

## Expected Folder Structure

```
<experiment_root>/
└── PostProcessing/
    ├── CropRaw/    # input videos, *_crop.avi or *_crop.mp4
    ├── Arenas/     # arena reference images (.png), used to read real-world dimensions
    ├── Tracked/    # Bonsai centroid CSVs, *_tracked.csv
    ├── Pose/       # output: generated pose CSVs, *_pose.csv
    └── Temp_SLP/   # intermediate SLEAP .slp prediction files
```

## Output Data Convention

The generated CSV files (one per video, in `PostProcessing/Pose/`) are structured for seamless integration with downstream analysis tools:
* **FrameIndex:** Sequential video frame index.
* **[Node].Position.X / Y:** Normalized coordinates ($0.0$–$1.0$, relative to the arena).
* **[Node].Confidence:** Model confidence score ($0.0$ to $1.0$).

**Naming convention:** for a video named `<id>_crop.avi`, the pipeline looks for the matching Bonsai CSV at `<id_with _crop replaced by _tracked>_tracked.csv`, and for the arena reference image first at `<id>.png` (per-fly), falling back to `<id without the _flyN suffix>.png` (shared per recording session).

---

## References & Credits
* **SLEAP Paper:** [Pereira et al., Nature Methods (2022)](https://doi.org/10.1038/s41592-022-01426-1)
* **Laboratory:** [Moita Lab](https://moitalab.org/) — Champalimaud Foundation
* **Official Documentation:** [sleap.ai](https://sleap.ai/)

---
**Developed by Rodrigo Garrido / Moita Lab**
