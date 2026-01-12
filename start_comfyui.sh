#!/bin/bash

# ComfyUI tag initial value
export COMFYUI_TAG="v0.8.0"

if [ -f ./env ]; then
  set -a
  source ./env
  set +a
fi

# ComfyUIのコンテナを実行(1GPU想定)
podman container run -d --replace \
  --name comfyui-running-on-runpod \
  -p 8188:8188 \
  -p 8888:8888 \
  --volume "$(pwd)/data:/workspace/data" \
  --volume "$(pwd)/output:/workspace/output" \
  --device "nvidia.com/gpu=all" \
  --env NUMBER_OF_GPUS=1 \
  --env "ENABLED_COMFYUI_PREVIEW_GALLERY=${ENABLED_COMFYUI_PREVIEW_GALLERY:-'false'}" \
  --env "ENABLED_WAN2_MODELS_DOWNLOAD=${ENABLED_WAN2_MODELS_DOWNLOAD:-'false'}" \
  --env "ENABLED_FLUX2_MODELS_DOWNLOAD=${ENABLED_FLUX2_MODELS_DOWNLOAD:-'false'}" \
  --env "ENABLED_QWENIMAGE_MODELS_DOWNLOAD=${ENABLED_QWENIMAGE_MODELS_DOWNLOAD:-'false'}" \
  localhost/comfyui-running-on-runpod:${COMFYUI_TAG:-"latest"}

podman container logs -f comfyui-running-on-runpod

#  --env "ENABLED_WAN2_MODELS_CHECKSUM=${ENABLED_WAN2_MODELS_CHECKSUM:-'false'}" \
#  --env "ENABLED_FLUX2_MODELS_CHECKSUM=${ENABLED_FLUX2_MODELS_CHECKSUM:-'false'}" \
#  --env "ENABLED_QWENIMAGE_MODELS_CHECKSUM=${ENABLED_QWENIMAGE_MODELS_CHECKSUM:-'false'}" \
