#!/usr/bin/env bash

MODEL_HOME="$HOME/models"
mkdir -p "$MODEL_HOME"

MODEL_REPO=(
    "TheBloke/Mistral-7B-Instruct-v0.2-GGUF"
    "lmstudio-community/Meta-Llama-3-8B-Instruct-GGUF" 
    "Qwen/Qwen2.5-7B-Instruct-GGUF" 
    "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF" 
    "unsloth/gemma-4-12b-it-GGUF"
    "unsloth/gpt-oss-20b-GGUF"
)
MODEL_FILES=(
    "mistral-7b-instruct-v0.2.Q4_K_M.gguf"
    "Meta-Llama-3-8B-Instruct-Q4_K_M.gguf"
    "qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf"
    "qwen2.5-coder-7b-instruct-q4_k_m-00001-of-00002.gguf qwen2.5-coder-7b-instruct-q4_k_m-00002-of-00002.gguf"
    "gemma-4-12b-it-Q4_K_M.gguf"
    "gpt-oss-20b-Q4_K_M.gguf"
)
MODEL_INTO=(
    "$MODEL_HOME/mistral-7b"
    "$MODEL_HOME/llama3-8b"
    "$MODEL_HOME/qwen2.5-7b"
    "$MODEL_HOME/qwen2.5-coder-7b"
    "$MODEL_HOME/gemma-4-12b"
    "$MODEL_HOME/gpt-oss-20b"
) 
MODEL_NAME=(
    "Mistral-7B-Q4_K_M"
    "Llama-3-8B-Q4_K_M"
    "Qwen2.5-7B-Q4_K_M"
    "Qwen2.5-Coder-7B-Q4_K_M"
    "Gemma-4-12B-it-Q4_K_M"
    "GPT-OSS-20B-Q4_K_M"
)

model_download() {
    local model_repo="${MODEL_REPO[$1]}"
    local model_files="${MODEL_FILES[$1]}"
    local model_into="${MODEL_INTO[$1]}"

    echo "
----------------------------------------
From     : $model_repo 
Download : $model_files
Into     : $model_into
----------------------------------------"

    mkdir -p "$model_into" || {
        echo "ERROR cannot create directory: $model_into"
        return 1
    } 
    (
        cd "$model_into" || {
            echo "ERROR cannot change directory to: $model_into"
            return 1
        }
        for file in $model_files; do
            echo "... download $file"
            hf download "$model_repo" \
                --local-dir "$model_into" \
                --include "$file"

            if [ -L "$file" ]; then
                echo "... converting symlink to hard link: $file"
                target=$(readlink "$file")
                rm "$file"
                ln "$target" "$file"
            else
                echo "... file is already real: $file"
            fi
        done
    )
}

OPTIONS_LLAMA_BENCH="
-p 512,2048,4096 
-n 128 
-ngl 99 
-r 3
"

model_benchmark() {
    local model_path="${MODEL_INTO[$1]}/$(echo ${MODEL_FILES[$1]} | awk '{print $1}')"
    local model_name="${MODEL_NAME[$1]}"
    local model_out="$MODEL_HOME/benchmark_$model_name.txt"

    echo "
----------------------------------------
Benchmark : $model_name
Save to   : $model_out
----------------------------------------"

    # Run llama.cpp benchmark
    (
        set -x
        llama-bench $OPTIONS_LLAMA_BENCH -m "$model_path"
        
    ) | tee "$model_out"
}

# Download models.
model_download 0    # Mistral
model_download 1    # Llama-3-8B
model_download 2    # Qwen2.5-7B
model_download 3    # Qwen2.5-Coder-7B
model_download 4    # Gemma-4-12B
model_download 5    # GPT-OSS-20B

model_benchmark 0   # Mistral
model_benchmark 1   # Llama-3-8B
model_benchmark 2   # Qwen2.5-7B
model_benchmark 3   # Qwen2.5-Coder-7B
model_benchmark 4   # Gemma-4-12B
model_benchmark 5   # GPT-OSS-20B
echo "
----------------------------------------
All models downloaded, symlinks fixed, and benchmarks completed.
----------------------------------------"
