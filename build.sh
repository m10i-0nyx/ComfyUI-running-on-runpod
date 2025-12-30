#!/bin/bash

set -Eeuo pipefail

# ComfyUI tag initial value
export COMFYUI_TAG=""

if [ -f ./.env ]; then
  set -a
  source ./.env
  set +a
fi

# ComfyUIのコンテナをビルド
podman build -t comfyui-runpod:${COMFYUI_TAG:-"latest"} \
  --force-rm \
  --build-arg COMFYUI_TAG=${COMFYUI_TAG} \
  --env ENABLED_COMFYUI_PREVIEW_GALLERY=${ENABLED_COMFYUI_PREVIEW_GALLERY:-"false"} \
  --env "ENABLED_WAN2_MODELS_DOWNLOAD=${ENABLED_WAN2_MODELS_DOWNLOAD:-"false"}" \
  --env "ENABLED_WAN2_MODELS_CHECKSUM=${ENABLED_WAN2_MODELS_CHECKSUM:-"false"}" \
  --env "ENABLED_FLUX2_MODELS_DOWNLOAD=${ENABLED_FLUX2_MODELS_DOWNLOAD:-"false"}" \
  --env "ENABLED_FLUX2_MODELS_CHECKSUM=${ENABLED_FLUX2_MODELS_CHECKSUM:-"false"}" \
  --env "ENABLED_QWENIMAGE_MODELS_DOWNLOAD=${ENABLED_QWENIMAGE_MODELS_DOWNLOAD:-"false"}" \
  --env "ENABLED_QWENIMAGE_MODELS_CHECKSUM=${ENABLED_QWENIMAGE_MODELS_CHECKSUM:-"false"}" \
  --device "nvidia.com/gpu=all" \
  ./services/comfyui/
