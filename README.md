# Colab_SLEAP: Automated Colab Pipeline & Pre-trained Model

This repository provides an end-to-end solution for animal pose estimation using **SLEAP (Social LEAP Estimates Animal Poses)**. It features two automated Google Colab workflows designed for high-throughput batch processing, paired with a pre-trained UNet model optimized for single-animal tracking.

---

## The Notebooks

Both notebooks are engineered for performance in the cloud, leveraging **NVIDIA Tesla T4 GPUs**, and are specifically tailored to recognize and navigate the **Moita Lab** data structure automatically. They run the exact same pipeline — they only differ in where the trained model comes from.

| Notebook | Model source |
| :--- | :--- |
| `Colab_SLEAP_AI_GITHUB.ipynb` | Clones the trained model straight from the [moitalab/Sleap_Colab](https://github.com/moitalab/Sleap_Colab) GitHub repository. |
| `Colab_SLEAP_AI_DRIVE.ipynb` | Loads the trained model from a folder in your own Google Drive, picked with a file chooser — no GitHub access needed. |

The system used is `condacolab`, which helps bypass Colab's default Python limitations so SLEAP can run inside an environment with the necessary drivers.

### Key Features:
* **Automated Hierarchy Management:** Point the notebook at an "Experiment" root folder, and it automatically locates `/PostProcessing/CropRaw` for videos and `/PostProcessing/Arenas` for normalization data.
* **Dynamic Normalization:** Instead of fixed scaling, the pipeline reads the `.png` arena files to ensure coordinates are perfectly normalized ($0.0$ to $1.0$) based on the specific resolution of each session.
* **Environment Integrity:** Uses `condacolab` and `mamba` to build a clean SLEAP v1.3.4 environment with optimized TensorFlow and CUDA drivers.

### How to Use:
1. **Define Paths:** Run the initialization cell to mount your Google Drive and select your **Experiment Root Folder** (and, in the Drive notebook, the **Model Folder** too). The script verifies the internal folder structure and creates a `Pose` subfolder for the results.
2. **Prepare the Environment:** Run the setup cells to build the Conda environment and dependencies via `condacolab` + `mamba`. **The kernel restarts after this step** — re-run the *Define Paths* cell before running the final pipeline cell.
3. **Run SLEAP:** Execute the final tracking cell. The script processes all `.avi` files in `CropRaw` and outputs both `.slp` (SLEAP) and `_pose.csv` (Bonsai-ready) files.

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
