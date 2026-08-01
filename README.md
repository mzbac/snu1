# SNU1 CUDA container

This repository publishes a binary-only container for native SenseNova-U1
text-to-image generation and image editing on supported NVIDIA GPUs. It serves
an OpenAI-compatible Images API and does not contain model weights or SNU1
implementation source.

The container includes the compiled `snu1` executable, its operating-system
runtime, and redistribution notices. Supply the base model and optional LoRA
as read-only files at runtime, subject to their own license terms.

## Requirements

- Linux AMD64
- NVIDIA Ada SM89 GPU with 24 GiB VRAM
- NVIDIA driver compatible with CUDA 12.8
- Docker Engine with NVIDIA Container Toolkit configured
- released CUDA profile-v2 FP8 base GGUF
- released native-FP8 LoRA GGUF when using the 8-step model

The `0.1.0` CUDA image is qualified on an RTX 4090 for the SM89 build target.
Lower-memory SM89 GPUs are not supported. This is not a portable CPU image and
is not intended for other CUDA compute capabilities.

## Pull and verify

Prefer a version-specific image tag over a moving tag. Pin its published
manifest digest when deployment reproducibility is required:

```sh
SNU1_IMAGE=ghcr.io/mzbac/snu1:0.1.0-cuda12.8-sm89
docker pull "$SNU1_IMAGE"
```

Confirm that the driver, GPU, and embedded CUDA kernels are usable before
loading model weights:

```sh
docker run --rm --gpus '"device=0"' "$SNU1_IMAGE" doctor
docker run --rm --gpus '"device=0"' "$SNU1_IMAGE" kernel-smoke
```

## Download the model files

Download the two CUDA GGUF files from Hugging Face:

- [SenseNova-U1-8B-MoT-Infographic-V3-FP8.gguf](https://huggingface.co/mzbac/SenseNova-U1-8B-MoT-Infographic-V3-Q8_0/blob/main/SenseNova-U1-8B-MoT-Infographic-V3-FP8.gguf)
  is the full base model.
- [SenseNova-U1-8B-MoT-Infographic-LoRA-8step-V1.0-FP8.gguf](https://huggingface.co/mzbac/SenseNova-U1-8B-MoT-Infographic-V3-Q8_0/blob/main/SenseNova-U1-8B-MoT-Infographic-LoRA-8step-V1.0-FP8.gguf)
  is the optional 8-step LoRA.

The files are large. These commands pin the current model-repository revision,
resume an interrupted download, and verify both files before use:

```sh
SNU1_MODEL_DIR=/absolute/path/to/snu1-models
SNU1_MODEL_REVISION=7f8dea0ec7f8335b1ec7f11a6eb3d51b982f371c
mkdir -p "$SNU1_MODEL_DIR"

curl --fail --location --retry 3 --continue-at - \
  --output "$SNU1_MODEL_DIR/SenseNova-U1-8B-MoT-Infographic-V3-FP8.gguf" \
  "https://huggingface.co/mzbac/SenseNova-U1-8B-MoT-Infographic-V3-Q8_0/resolve/${SNU1_MODEL_REVISION}/SenseNova-U1-8B-MoT-Infographic-V3-FP8.gguf?download=true"

curl --fail --location --retry 3 --continue-at - \
  --output "$SNU1_MODEL_DIR/SenseNova-U1-8B-MoT-Infographic-LoRA-8step-V1.0-FP8.gguf" \
  "https://huggingface.co/mzbac/SenseNova-U1-8B-MoT-Infographic-V3-Q8_0/resolve/${SNU1_MODEL_REVISION}/SenseNova-U1-8B-MoT-Infographic-LoRA-8step-V1.0-FP8.gguf?download=true"

(
  cd "$SNU1_MODEL_DIR"
  printf '%s  %s\n' \
    '0ca3f358d69b94f57118e0e9231688a95ddb2d13117f2795a04a2b286374add3' \
    'SenseNova-U1-8B-MoT-Infographic-V3-FP8.gguf' \
    '260aa366b3d92cf0364028f54f24e29e3c327fcc722d6949e0e9d4ef328f8cd6' \
    'SenseNova-U1-8B-MoT-Infographic-LoRA-8step-V1.0-FP8.gguf' |
    sha256sum --check
)
```

## Start the Images API

Point these variables at the downloaded files:

```sh
SNU1_BASE_GGUF="$SNU1_MODEL_DIR/SenseNova-U1-8B-MoT-Infographic-V3-FP8.gguf"
SNU1_LORA_GGUF="$SNU1_MODEL_DIR/SenseNova-U1-8B-MoT-Infographic-LoRA-8step-V1.0-FP8.gguf"
```

The default command expects both files. It loads the base model and registers
the LoRA so every generation or edit request can choose either execution mode:

```sh
docker run --rm \
  --gpus '"device=0"' \
  --user "$(id -u):$(id -g)" \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=256m \
  --stop-timeout 300 \
  -p 127.0.0.1:8080:8080 \
  --mount "type=bind,src=${SNU1_BASE_GGUF},dst=/models/base.gguf,readonly" \
  --mount "type=bind,src=${SNU1_LORA_GGUF},dst=/models/lora.gguf,readonly" \
  "$SNU1_IMAGE"
```

The command runs in the foreground. Keep that terminal open, then use another
terminal for API requests. `--user "$(id -u):$(id -g)"` gives the non-root
container process the numeric identity used to read the selected model files.

Check readiness and discover the available model IDs:

```sh
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS http://127.0.0.1:8080/v1/models
```

The server advertises these request-time choices:

| `model` value | Execution mode |
| --- | --- |
| `sensenova-u1-v3` | full base model, 50 steps and CFG 4 |
| `sensenova-u1-v3-infographic-8step` | official LoRA, 8 steps and CFG 1 |

Registering the LoRA at server startup does not make it the default. Its factor
tensors load lazily on the first LoRA request. The `model` field on each
generation or edit request independently selects base or LoRA; omitting
`model` selects the base model.

## Generate an image

Use the 8-step LoRA for text-to-image generation:

```sh
curl -sS http://127.0.0.1:8080/v1/images/generations \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "sensenova-u1-v3-infographic-8step",
    "prompt": "Create a clean, information-dense infographic about renewable energy.",
    "size": "1024x1024",
    "quality": "high",
    "n": 1
  }' \
  -o generation-response.json
```

## Edit an image

Send one PNG, JPEG, or WebP file as multipart form data. This example also
uses the 8-step LoRA:

```sh
curl -sS http://127.0.0.1:8080/v1/images/edits \
  -F 'model=sensenova-u1-v3-infographic-8step' \
  -F 'prompt=Change the main title to Renewable Energy while preserving the layout.' \
  -F 'image[]=@input.png;type=image/png' \
  -F 'input_fidelity=high' \
  -F 'size=auto' \
  -o edit-response.json
```

Change `model` to `sensenova-u1-v3` when full 50-step generation or editing is
preferred. Successful responses contain the output PNG as base64 in
`.data[0].b64_json`. On a Linux client with `jq` and GNU `base64`, decode it
with:

```sh
jq -r '.data[0].b64_json' generation-response.json | base64 --decode > generated.png
jq -r '.data[0].b64_json' edit-response.json | base64 --decode > edited.png
```

The API supports one output per request. Image edits accept exactly one input
file no larger than 20 MiB. Output dimensions must be at least 256, divisible
by 32, stay between a 1:3 and 3:1 aspect ratio, and contain no more than
4,194,304 pixels.

## Run without LoRA

To expose only the full base model, omit the LoRA mount and replace the image's
complete default command:

```sh
docker run --rm \
  --gpus '"device=0"' \
  --user "$(id -u):$(id -g)" \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=256m \
  --stop-timeout 300 \
  -p 127.0.0.1:8080:8080 \
  --mount "type=bind,src=${SNU1_BASE_GGUF},dst=/models/base.gguf,readonly" \
  "$SNU1_IMAGE" \
  serve --model_path /models/base.gguf \
  --host 0.0.0.0 --port 8080 --allow-remote
```

In this mode, `/v1/models` advertises only `sensenova-u1-v3`.

## Network safety

The native server provides neither TLS nor authentication. The examples bind
the host port to loopback so only local clients can connect. For remote access,
place the container behind an authenticated TLS reverse proxy instead of
publishing port 8080 directly.

A same-origin browser frontend needs no CORS setting. For a frontend on a
different origin, replace the complete default command and add one exact
`--cors-origin`, such as `https://app.example`. CORS is a browser policy, not
authentication.

## Image tags

Version-specific tags:

```text
ghcr.io/mzbac/snu1:0.1.0
ghcr.io/mzbac/snu1:0.1.0-cuda12.8-sm89
```

Moving tags for the latest stable release:

```text
ghcr.io/mzbac/snu1:latest
ghcr.io/mzbac/snu1:cuda12.8-sm89
```

GHCR tags can be replaced. Pin the published manifest digest when deployment
reproducibility must be enforced.
