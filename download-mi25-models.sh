#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/models"
mkdir -p "$BASE_DIR"

download_and_fix() {
    local repo="$1"
    local pattern="$2"
    local outdir="$3"

    echo "----------------------------------------"
    echo "Downloading $pattern from $repo"
    echo "----------------------------------------"

    mkdir -p "$outdir"

    hf download "$repo" \
        --local-dir "$outdir" \
        --include "$pattern"

    cd "$outdir"
    local fname="$(basename "$pattern")"
    if [ -L "$fname" ]; then
        echo "Converting symlink to real file: $fname"
        cp --dereference "$fname" "$fname.real"
        mv "$fname.real" "$fname"
    else
        echo "File is already real: $fname"
    fi

    echo "Done: $outdir/$fname"
    echo
}

# Mistral‑7B‑Instruct‑v0.2 (Q4_K_M)
download_and_fix \
    "TheBloke/Mistral-7B-Instruct-v0.2-GGUF" \
    "mistral-7b-instruct-v0.2.Q4_K_M.gguf" \
    "$BASE_DIR/mistral-7b"

# Llama‑3‑8B‑Instruct (Q4_K_M)
download_and_fix \
    "lmstudio-community/Meta-Llama-3-8B-Instruct-GGUF" \
    "Meta-Llama-3-8B-Instruct-Q4_K_M.gguf" \
    "$BASE_DIR/llama3-8b"

# Qwen2.5‑7B‑Instruct (Q4_K_M) — SHARDED
download_and_fix \
    "Qwen/Qwen2.5-7B-Instruct-GGUF" \
    "qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf" \
    "$BASE_DIR/qwen2.5-7b"

download_and_fix \
    "Qwen/Qwen2.5-7B-Instruct-GGUF" \
    "qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf" \
    "$BASE_DIR/qwen2.5-7b"

# Qwen2.5‑Coder‑7B‑Instruct (Q4_K_M) — SHARDED
download_and_fix \
    "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF" \
    "qwen2.5-coder-7b-instruct-q4_k_m-00001-of-00002.gguf" \
    "$BASE_DIR/qwen2.5-coder-7b"

download_and_fix \
    "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF" \
    "qwen2.5-coder-7b-instruct-q4_k_m-00002-of-00002.gguf" \
    "$BASE_DIR/qwen2.5-coder-7b"

echo "----------------------------------------"
echo "All models downloaded and symlinks fixed."
echo "----------------------------------------"

echo
echo "Run commands:"
echo "----------------------------------------"
echo "llama cli -m $BASE_DIR/mistral-7b/mistral-7b-instruct-v0.2.Q4_K_M.gguf -p \"Test Mistral on MI25\""
echo "llama cli -m $BASE_DIR/llama3-8b/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf -p \"Test Llama 3 on MI25\""
echo "llama cli -m $BASE_DIR/qwen2.5-7b/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf -p \"Test Qwen2.5 on MI25\""
echo "llama cli -m $BASE_DIR/qwen2.5-coder-7b/qwen2.5-coder-7b-instruct-q4_k_m-00001-of-00002.gguf -p \"Test Qwen2.5 Coder on MI25\""
echo "----------------------------------------"

