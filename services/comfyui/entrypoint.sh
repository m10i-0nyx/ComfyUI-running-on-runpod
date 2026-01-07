#!/bin/bash

set -Eeuo pipefail

# --- 1. ディレクトリ作成 ---
mkdir -p ${WORKSPACE}/data/.cache
mkdir -p ${WORKSPACE}/data/models/{checkpoints,clip_vision,controlnet,diffusion_models,gligen,hypernetworks,loras,text_encoders,upscale,vae}
mkdir -p ${WORKSPACE}/comfyui/custom_nodes

declare -A MOUNTS

MOUNTS["/root/.cache"]="${WORKSPACE}/data/.cache"
MOUNTS["${WORKSPACE}/input"]="${WORKSPACE}/data/config/input"
MOUNTS["/comfyui/output"]="${WORKSPACE}/output"

for to_path in "${!MOUNTS[@]}"; do
    set -Eeuo pipefail
    from_path="${MOUNTS[${to_path}]}"
    rm -rf "${to_path}"
    if [ ! -d "${from_path}" ]; then
        mkdir -vp "${from_path}"
    fi
    mkdir -vp "$(dirname "${to_path}")"
    ln -sT "${from_path}" "${to_path}"
    echo Mounted "$(basename "${from_path}")"
done

# --- 2. Python venv activate & exec ---
. ${VENV_PATH}/bin/activate

# --- 3. Print system info ---
echo "===== ComfyUI Entrypoint Info ====="
echo "Workspace: ${WORKSPACE}"
echo "Venv: ${VENV_PATH}"
echo "Python: $(which python) ($(python --version))"
echo "----- torch info -----"
python -c "import torch; print('torch=', torch.__version__); print('torch_cuda=', torch.version.cuda); print('avail=', torch.cuda.is_available())"

export TORCH_CUDA_AVAILABLE=$(python -c "import torch; print(torch.cuda.is_available())")
if [ "${TORCH_CUDA_AVAILABLE}" = "False" ]; then
    echo "CUDA is not available. Dropping to shell for debugging."
    exec /bin/bash || exec /bin/sh
fi

# --- 4. safetensors の自動ダウンロード機能 ---
export DOWNLOAD_LIST="/container/download_list.txt"
export CHECKSUM_LIST="/container/checksum_list.txt"
export DOWNLOAD_DIR="${WORKSPACE}/data/models"

rm -f "${DOWNLOAD_LIST}" >/dev/null 2>&1
rm -f "${CHECKSUM_LIST}" >/dev/null 2>&1

# Wan2.2 Models
if [ -z "${ENABLED_WAN2_MODELS_DOWNLOAD:-''}" ] && [ "${ENABLED_WAN2_MODELS_DOWNLOAD:-'false'}" = "true" ]; then
    echo "WAN2 Models download enabled."
    cat /container/preset_lists/download_wan2.txt >> "${DOWNLOAD_LIST}"
fi
if [ -z "${ENABLED_WAN2_MODELS_CHECKSUM:-''}" ] && [ "${ENABLED_WAN2_MODELS_CHECKSUM:-'false'}" = "true" ]; then
    echo "WAN2 Models checksum verification enabled."
    cat /container/preset_lists/checksum_wan2.txt >> "${CHECKSUM_LIST}"
fi

# FLUX.2 Models
if [ -z "${ENABLED_FLUX2_MODELS_DOWNLOAD:-''}" ] && [ "${ENABLED_FLUX2_MODELS_DOWNLOAD:-'false'}" = "true" ]; then
    echo "FLUX.2 Models download enabled."
    cat /container/preset_lists/download_flux2.txt >> "${DOWNLOAD_LIST}"
fi
if [ -z "${ENABLED_FLUX2_MODELS_CHECKSUM:-''}" ] && [ "${ENABLED_FLUX2_MODELS_CHECKSUM:-'false'}" = "true" ]; then
    echo "FLUX.2 Models checksum verification enabled."
    cat /container/preset_lists/checksum_flux2.txt >> "${CHECKSUM_LIST}"
fi

# Qwen-Image Models
if [ -z "${ENABLED_QWENIMAGE_MODELS_DOWNLOAD:-''}" ] && [ "${ENABLED_QWENIMAGE_MODELS_DOWNLOAD:-'false'}" = "true" ]; then
    echo "Qwen-Image Models download enabled."
    cat /container/preset_lists/download_qwenimage.txt >> "${DOWNLOAD_LIST}"
fi
if [ -z "${ENABLED_QWENIMAGE_MODELS_CHECKSUM:-''}" ] && [ "${ENABLED_QWENIMAGE_MODELS_CHECKSUM:-'false'}" = "true" ]; then
    echo "Qwen-Image Models checksum verification enabled."
    cat /container/preset_lists/checksum_qwenimage.txt >> "${CHECKSUM_LIST}"
fi

# Custom user lists
if [ -f "${DOWNLOAD_DIR}/download_list.txt" ]; then
    echo "Custom download list found in download directory. Appending to download list."
    cat "${DOWNLOAD_DIR}/download_list.txt" >> "${DOWNLOAD_LIST}"
fi
if [ -f "${DOWNLOAD_DIR}/checksum_list.txt" ]; then
    echo "Custom checksum list found in download directory. Appending to checksum list."
    cat "${DOWNLOAD_DIR}/checksum_list.txt" >> "${CHECKSUM_LIST}"
fi

if [ -f "${DOWNLOAD_LIST}" ]; then
    echo "${DOWNLOAD_LIST} found. Starting aria2c downloads..."
    mkdir -p "$DOWNLOAD_DIR"

    aria2c \
        --continue=true \
        --allow-overwrite=false \
        --auto-file-renaming=false \
        --max-connection-per-server=4 \
        --split=16 \
        --dir="${DOWNLOAD_DIR}" \
        --input-file="${DOWNLOAD_LIST}"

    echo "Download finished."
else
    echo "No ${DOWNLOAD_LIST} found. Skipping download."
fi

if [ -f "${CHECKSUM_LIST}" ]; then
    echo "${CHECKSUM_LIST} found. Starting sha256sum verification..."

    grep -E -v '^[#|;]' "${CHECKSUM_LIST}" | parallel --will-cite -n1 'echo -n {} | sha256sum -c'

    echo "Checksum verification finished."
else
    echo "No ${CHECKSUM_LIST} found. Skipping checksum verification."
fi

# --- 5. startup.sh があれば実行 ---
if [ -f "${WORKSPACE}/comfyui/startup.sh" ]; then
    pushd ${WORKSPACE}/comfyui
    . ${WORKSPACE}/comfyui/startup.sh
    popd
fi

# --- 6. コマンド実行 ---
exec "$@"
