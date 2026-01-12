#!/bin/bash

set -Eeuo pipefail

# --- 1. ディレクトリ作成 ---
mkdir -p ${WORKSPACE}/data/.cache
mkdir -p ${WORKSPACE}/data/comfyui/custom_nodes
mkdir -p ${WORKSPACE}/data/models/{checkpoints,clip_vision,configs,controlnet,diffusion_models,unet,hypernetworks,loras,text_encoders,upscale_models,vae,audio_encoders,model_patches,latent_upscale_models}

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
    echo "sleeping infinity..."
    sleep infinity
fi

# --- 4. カスタムノードをインストール ---

# ComfyUI-Impact-Pack ノードをインストール
pushd "${WORKSPACE}/data/comfyui/custom_nodes"
if [ ! -d "comfyui-impact-pack" ] || [ "${FORCE_UPGRADE_CUSTOM_NODES:-'false'}" = "true" ] ; then
    echo "Installing/upgrading ComfyUI-Impact-Pack..."
    rm -rf comfyui-impact-pack >/dev/null 2>&1
    git clone -b Main --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git comfyui-impact-pack
fi
cd comfyui-impact-pack
uv pip install -r requirements.txt
popd

# comfyui-crystools ノードをインストール
pushd "${WORKSPACE}/data/comfyui/custom_nodes"
if [ ! -d "comfyui-crystools" ] || [ "${FORCE_UPGRADE_CUSTOM_NODES:-'false'}" = "true" ] ; then
    echo "Installing/upgrading comfyui-crystools..."
    rm -rf comfyui-crystools >/dev/null 2>&1
    git clone -b main --depth 1 https://github.com/crystian/comfyui-crystools.git comfyui-crystools
fi
cd comfyui-crystools
uv pip install -r requirements.txt
popd

# ComfyUI-Custom-Scripts ノードをインストール
pushd "${WORKSPACE}/data/comfyui/custom_nodes"
if [ ! -d "comfyui-custom-scripts" ] || [ "${FORCE_UPGRADE_CUSTOM_NODES:-'false'}" = "true" ] ; then
    echo "Installing/upgrading ComfyUI-Custom-Scripts..."
    rm -rf comfyui-custom-scripts >/dev/null 2>&1
    git clone -b main --depth 1 https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git comfyui-custom-scripts
fi
popd

# ComfyUI-Autocomplete-Plus ノードをインストール
pushd "${WORKSPACE}/data/comfyui/custom_nodes"
if [ ! -d "comfyui-autocomplete-plus" ] || [ "${FORCE_UPGRADE_CUSTOM_NODES:-'false'}" = "true" ] ; then
    echo "Installing/upgrading ComfyUI-Autocomplete-Plus..."
    rm -rf comfyui-autocomplete-plus >/dev/null 2>&1
    git clone -b main --depth 1 https://github.com/newtextdoc1111/ComfyUI-Autocomplete-Plus.git comfyui-autocomplete-plus
fi
popd

# ComfyUI-ppm ノードをインストール
pushd "${WORKSPACE}/data/comfyui/custom_nodes"
if [ ! -d "comfyui-ppm" ] || [ "${FORCE_UPGRADE_CUSTOM_NODES:-'false'}" = "true" ] ; then
    echo "Installing/upgrading ComfyUI-ppm..."
    rm -rf comfyui-ppm >/dev/null 2>&1
    git clone -b master --depth 1 https://github.com/pamparamm/ComfyUI-ppm.git comfyui-ppm
fi
popd

# matrix-nio をインストール(ComfyUI-Manager 用)
uv pip install matrix-nio

# pynvml を nvidia-ml-py に置き換え
uv pip uninstall pynvml
uv pip install -U nvidia-ml-py

# --- 5. safetensors の自動ダウンロード機能 ---
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

# LTX2 Video Models
if [ -z "${ENABLED_LTX2_MODELS_DOWNLOAD:-''}" ] && [ "${ENABLED_LTX2_MODELS_DOWNLOAD:-'false'}" = "true" ]; then
    echo "LTX2 Video Models download enabled."
    cat /container/preset_lists/download_ltx2.txt >> "${DOWNLOAD_LIST}"
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

# --- 6. startup.sh があれば実行 ---
if [ -f "${WORKSPACE}/comfyui/startup.sh" ]; then
    pushd ${WORKSPACE}/comfyui
    . ${WORKSPACE}/comfyui/startup.sh
    popd
fi

# --- 7. コマンド実行 ---
pushd ${COMFYUI_DIR}
if [ ${NUMBER_OF_GPUS:-1} -gt 1 ]; then
    echo "***** Starting ${NUMBER_OF_GPUS} ComfyUI processes *****"
    LISTEN_PORT=${LISTEN_PORT:-8188}
    for ((idx=0; idx<${NUMBER_OF_GPUS}; idx++)); do
        CURRENT_PORT=$(($LISTEN_PORT + $idx))
        echo "***** Starting ComfyUI process $(($idx+1))/${NUMBER_OF_GPUS} on port ${CURRENT_PORT} with GPU ${idx} *****"
        CUDA_VISIBLE_DEVICES=${idx} python3 -u main.py --listen 0.0.0.0 --port ${CURRENT_PORT} ${CLI_ARGS} &
    done
else
    echo "***** Starting ComfyUI processes *****"
    python3 -u main.py --listen 0.0.0.0 --port 8188 ${CLI_ARGS} &
fi
popd

# --- 7. start preview gallery ---
if [ -z "${ENABLED_COMFYUI_PREVIEW_GALLERY:-''}" ] && [ "${ENABLED_COMFYUI_PREVIEW_GALLERY:-'false'}" = "true" ]; then
    python3 -u /container/preview_gallery.py &
fi

wait
