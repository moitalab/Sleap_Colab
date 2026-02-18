# Colab_SLEAP: Automated Colab Pipeline & Pre-trained Model

This repository provides an end-to-end solution for animal pose estimation using **SLEAP (Social LEAP Estimates Animal Poses)**. It features an automated Google Colab workflow designed for high-throughput batch processing and a pre-trained UNet model optimized for single-animal tracking.

---

##  The Notebook: `Colab_SLEAP_AI.ipynb`

This notebook is engineered for performance in the cloud, leveraging **NVIDIA Tesla T4 GPUs**. It is specifically tailored to recognize and navigate the **Moita Lab** data structure automatically.

### Key Features:
* **Automated Hierarchy Management:** Point the notebook at an "Experience" root folder, and it automatically locates `/PostProcessing/CropRaw` for videos and `/PostProcessing/Arenas` for normalization data.
* **Dynamic Normalization:** Instead of fixed scaling, the pipeline reads the `.png` arena files to ensure coordinates are perfectly normalized ($0.0$ to $1.0$) based on the specific resolution of each session.
* **Environment Integrity:** Uses `condacolab` and `mamba` to build a clean SLEAP v1.3.4 environment with optimized TensorFlow and CUDA drivers.


### How to Use:
1.  **Mount Drive:** Run the initialization cell to connect your Google Drive.
2.  **Synchronize Pipeline:** Select your **Experience Root Folder**. The script verifies the internal folder structure and creates a `Pose` subfolder for all results.
3.  **Install Environment:** Run the setup cells to configure the Conda environment and dependencies.
4.  **Run Pipeline:** Execute the final tracking cell. The script will process all `.avi` files and output both `.slp` (SLEAP) and `_pose.csv` (Bonsai-ready) files.

---

##  Model Specifications: `251125_130445`

The provided model is a high-accuracy **Single Instance** tracker utilizing a specialized UNet architecture.

| Feature | Details |
| :--- | :--- |
| **Architecture** | UNet (16 filters, 1 stack) |
| **Input Resolution** | 128 x 128 pixels |
| **Training Set** | ~3,283 labeled frames |
| **Context** | Optimized for complex "dirt/substrate" backgrounds |
| **Data Augmentation** | Rotation ($\pm 180^\circ$), Scaling ($0.4x$–$1.6x$) |

###  Skeleton (Keypoints)
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

##  Output Data Convention
The generated CSV files are structured for seamless integration with downstream analysis tools:
* **FrameIndex:** Sequential video frame index.
* **[Node].Position.X / Y:** Normalized coordinates ($Pixel / Resolution$).
* **[Node].Confidence:** Model confidence score ($0.0$ to $1.0$). 

---

##  References & Credits
* **SLEAP Paper:** [Pereira et al., Nature Methods (2022)](https://doi.org/10.1038/s41592-022-01426-1)
* **Laboratory:** [Moita Lab - Champalimaud Unknown](https://moitalab.org/)
* **Official Documentation:** [sleap.ai](https://sleap.ai/)

---
**Developed by Rodrigo Garrido / Moita Lab**
