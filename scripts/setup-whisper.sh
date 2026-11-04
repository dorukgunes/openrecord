#!/usr/bin/env bash
# Installs whisper.cpp and downloads the speech + voice-activity models OpenRecord transcribes with.
set -euo pipefail

MODEL_DIR="${HOME}/Library/Application Support/OpenRecord/models"
WHISPER_MODEL="${OPENRECORD_WHISPER_MODEL_NAME:-ggml-large-v3-turbo-q5_0.bin}"
VAD_MODEL="ggml-silero-v5.1.2.bin"

download() {
  local name="$1" url="$2"
  if [[ -s "$MODEL_DIR/$name" ]]; then
    echo "Already present: $MODEL_DIR/$name"
    return
  fi
  echo "Downloading ${name}..."
  curl -L --fail --progress-bar -o "$MODEL_DIR/$name.partial" "$url"
  mv "$MODEL_DIR/$name.partial" "$MODEL_DIR/$name"
}

if ! command -v whisper-cli >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required: https://brew.sh" >&2
    exit 1
  fi
  brew install whisper-cpp
fi

mkdir -p "$MODEL_DIR"
download "$WHISPER_MODEL" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WHISPER_MODEL"
download "$VAD_MODEL" "https://huggingface.co/ggml-org/whisper-vad/resolve/main/$VAD_MODEL"

echo "whisper-cli: $(command -v whisper-cli)"
echo "models:      $MODEL_DIR"
