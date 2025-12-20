# ComfyUI running on runpod 

This repository provides a setup to run [ComfyUI](https://github.com/comfyanonymous/ComfyUI) on a Linux container using Podman/Docker.

## Prerequisites
- Runpod account with a GPU container
- GPU container with at NVIDIA RTX 4090

## Setup
1. Clone this repository to your local machine or directly to your Runpod container.
```bash
git clone https://github.com/m10i-0nyx/ComfyUI-running-on-runpod-container.git
cd ComfyUI-running-on-runpod-container
```

2. (Optional) Create an `env` file to specify the ComfyUI version you want to use. If not specified, it will use the default version defined in the `build.sh` script.
```bash
echo "COMFYUI_TAG=v0.5.NN" > env
```

3. Build the ComfyUI container.
```bash
./build.sh
```

4. Push the container to AWS Elastic Container Registry (ECR).
```bash
sed -i 's|export AWS_PUBLIC_ECR_URL=.*$|export AWS_PUBLIC_ECR_URL="public.ecr.aws/{USER ECR}"|' push_aws_ecr.sh
./push_aws_ecr.sh
```

## Thanks

Special thanks to everyone behind these awesome projects, without them, none of this would have been possible:

- [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
