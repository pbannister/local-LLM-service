#!/usr/bin/env bash

WANT_SERVICE=${WANT_SERVICE-true}

SERVICE_NAME="llama.service"
$WANT_SERVICE && {
    echo "Stop: $SERVICE_NAME"
    sudo systemctl stop "$SERVICE_NAME" 
}

# Detect GPU and set GGML_VK_VISIBLE_DEVICES to the list of detected devices.
#
# $ llama-cli --list-devices
# Available devices:
#   Vulkan0: Radeon RX 5500 XT (RADV NAVI14) (8192 MiB, 4857 MiB free)
#
# $ llama-cli --list-devices
# Available devices:
#   Vulkan0: AMD Radeon Instinct MI25 (RADV VEGA10) (16368 MiB, 16343 MiB free)

DETECTED_DEVICES=($(
    {
        free -g -t 
        llama-cli --list-devices | grep Vulkan
    } | awk '
            BEGIN {
                DEVICE=9
                GB_FITS=64
                GPU="CPU"
            }
            /^Total:/ { 
                GB_FITS=$2
            }
            { 
                sub(/^  Vulkan/,"") 
                sub(/:/,"") 
            } 
            /Radeon Instinct MI25/ { 
                DEVICE=$1
                GB_FITS=16
                GPU="MI25"
            }
            /Radeon RX 5500 XT/ { 
                DEVICE=$1
                GB_FITS=6 # (8 - 2) for other processes
                GPU="RX5500XT"
            }
            END {
                print DEVICE " " GB_FITS " " GPU
            }
        '
))

# Use the detected device as the default.
# Set GB_FITS to the maximum number of GB that can fit on your GPU.  
# This is used to filter out models that are too large to fit on your GPU.  

export GGML_VK_VISIBLE_DEVICES="${GGML_VK_VISIBLE_DEVICES-${DETECTED_DEVICES[0]}}"
GB_FITS=${GB_FITS-${DETECTED_DEVICES[1]}}
GPU=${GPU-${DETECTED_DEVICES[2]}}

WANT_DOWNLOAD=${WANT_DOWNLOAD-true}
WANT_BENCHMARK=${WANT_BENCHMARK-true}

MODEL_HOME="$HOME/models"
mkdir -p "$MODEL_HOME"

LOGS_BASE="$MODEL_HOME/logs"
mkdir -p "$LOGS_BASE"

WHEN=$(date +%Y-%m-%d-%H-%M)
FILE_LOG="$LOGS_BASE/$WHEN-run-$HOSTNAME-$GPU.log"

MODEL_KEY=()
MODEL_FAMILY=()
MODEL_NAME=()
MODEL_SPEC=()

declare -A MODEL_OPTIONS

model_key_this=""

model_add() {
    local gb_wants="$1"
    [ "$GB_FITS" -lt "$gb_wants" ] && return 0
    local model_family="$2"
    local model_spec="$3"
    local model_name="$4"
    model_key_this="$(echo $model_family | sha256sum | awk '{print $1}')"
    MODEL_KEY+=("$model_key_this")
    MODEL_FAMILY+=("$model_family")
    MODEL_SPEC+=("$model_spec")
    MODEL_NAME+=("$model_name")
    MODEL_OPTIONS["$model_key_this"]=""
}

model_options() {
    MODEL_OPTIONS["$model_key_this"]="$*"
}

WANT_MODELS=${WANT_MODELS-true}

WANT_MODELS_COMPLETION=${WANT_MODELS_COMPLETION-${WANT_MODELS}}
WANT_MODELS_REASONING=${WANT_MODELS_REASONING-${WANT_MODELS}}
WANT_MODELS_CPU=${WANT_MODELS_CPU-${WANT_MODELS}}

# Selection of possibly-interesting models to download and benchmark.  
# These are all GGUF format models, which is the only format supported by llama.cpp for now.
# We are using the HuggingFace model spec format, which is <user>/<model-name>[:<quantization>].
# Models are downloaded into the HuggingFace cache, which is typically $HOME/.cache/huggingface/hub, 
# and then auto-discovered by llama.cpp when running benchmarks or the server.

# Keep in mind the GB_WANTS values are guessed.

$WANT_MODELS_COMPLETION && {
    # Fast Code Completion (Deterministic low temp, 8k context cap to keep latency sub-10ms)
    model_add  2    "Qwen-2.5-Coder-1.5B"               ":Q8_0"         "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF"
    model_options   "-c 8192 --temp 0.2 --top-p 0.95 -fa"

    model_add  4    "Qwen-2.5-Coder-3B"                 ":Q8_0"         "Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
    model_options   "-c 8192 --temp 0.2 --top-p 0.95 -fa"

    # Fast Desktop Generalists
    model_add  2    "Llama-3.2-1B"                      ":Q8_0"         "unsloth/Llama-3.2-1B-Instruct-GGUF"
    model_options   "-c 8192 --temp 0.6 --top-p 0.9 -fa"

    model_add  4    "Llama-3.2-3B"                      ":Q8_0"         "unsloth/Llama-3.2-3B-Instruct-GGUF"
    model_options   "-c 8192 --temp 0.6 --top-p 0.9 -fa"

    # Fast IDE Chat
    model_add  3    "Gemma-4-E2B-QAT"                   ":UD-Q4_K_XL"   "unsloth/gemma-4-E2B-it-qat-GGUF"         
    model_options   "-c 8192 --temp 0.7 -fa"

    model_add  6    "Gemma-4-E4B-QAT"                   ":UD-Q4_K_XL"   "unsloth/gemma-4-E4B-it-qat-GGUF"          
    model_options   "-c 8192 --temp 0.7 -fa"
}

$WANT_MODELS_REASONING && {
    # Agentic & Coding Workloads
    model_add 16    "Devstral-Small-2-24B"              ":Q4_K_M"       "unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF"       
    model_options   "-c 16384 --temp 0.15 --top-p 0.95 -fa"

    model_add 22    "Qwen-2.5-Coder-32B"                ":Q4_K_M"       "Qwen/Qwen2.5-Coder-32B-Instruct-GGUF"
    model_options   "-c 16384 --temp 0.2 --top-p 0.95 -fa"

    # High-Speed MoE on MI25 (Only 4B active parameters per token)
    model_add 15    "Gemma-4-26B-A4B-QAT"               ":UD-Q4_K_XL"   "unsloth/gemma-4-26B-A4B-it-qat-GGUF"
    model_options   "-c 16384 --temp 0.7 -fa"

    # DeepSeek R1 Reasoning Models (Official R1 recommendation: temp=0.6, top_p=0.95)
    model_add 10    "DeepSeek-R1-Distill-Qwen-14B"      ":UD-Q4_K_XL"   "unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF"
    model_options   "-c 16384 --temp 0.6 --top-p 0.95 -fa"

    model_add 22    "DeepSeek-R1-Distill-32B"           ":UD-Q4_K_XL"   "unsloth/DeepSeek-R1-Distill-Qwen-32B-GGUF"
    model_options   "-c 16384 --temp 0.6 --top-p 0.95 -fa"

    # General Chat & Tool Calling
    model_add 15    "GPT-OSS-20B"                       ":UD-Q4_K_XL"   "unsloth/gpt-oss-20b-GGUF"   
    model_options   "-c 16384 --temp 0.7 -fa"

    model_add  7    "Gemma-4-12B-QAT"                   ":UD-Q4_K_XL"   "unsloth/gemma-4-12B-it-qat-GGUF"          
    model_options   "-c 16384 --temp 0.7 -fa"

    model_add  8    "Mistral-Nemo-12B"                  ":Q4_K_M"       "unsloth/Mistral-Nemo-Base-2407-GGUF"
    model_options   "-c 16384 --temp 0.3 -fa"

    # Qwen 3.5 Models (Requires slight repeat penalty to prevent prompt loops)
    model_add  8    "Qwen-3.5-9B"                       ":Q4_K_M"       "unsloth/Qwen3.5-9B-GGUF"                           
    model_options   "-c 16384 --temp 0.7 --top-p 0.8 --repeat-penalty 1.05 -fa"

    model_add 18    "Qwen-3.5-27B"                      ":Q4_K_M"       "unsloth/Qwen3.5-27B-GGUF"                           
    model_options   "-c 16384 --temp 0.7 --top-p 0.8 --repeat-penalty 1.05 -fa"
}

$WANT_MODELS_CPU && {
    # Heavyweight CPU Workloads (Requires NUMA distribution across dual Xeon sockets)
    model_add 75    "GPT-OSS-120B"                      ":UD-Q4_K_XL"   "unsloth/gpt-oss-120b-GGUF"
    model_options   "-c 16384 --numa distribute --temp 0.7"

    model_add 45    "Llama-3.3-70B"                     ":UD-Q4_K_XL"   "unsloth/Llama-3.3-70B-Instruct-GGUF"
    model_options   "-c 16384 --numa distribute --temp 0.6 --top-p 0.9"

    model_add 45    "DeepSeek-R1-Distill-70B"           ":UD-Q4_K_XL"   "unsloth/DeepSeek-R1-Distill-Llama-70B-GGUF"
    model_options   "-c 16384 --numa distribute --temp 0.6 --top-p 0.95"

    # CPU-only testing models
    model_add  1    "Gemma-4-E2B-QAT-CPU"               ":UD-Q4_K_XL"   "unsloth/gemma-4-E2B-it-qat-GGUF"         
    model_options   "-c 8192 --temp 0.7"

    model_add  2    "Gemma-4-E4B-QAT-CPU"               ":UD-Q4_K_XL"   "unsloth/gemma-4-E4B-it-qat-GGUF"         
    model_options   "-c 8192 --temp 0.7"
}

OPTIONS_LLAMA_BENCH="
-p 512,2048,4096 
-n 128 
-ngl 99 
-r 3
"

# This prompt is for testing the model's ability to summarize a book. It is not related to coding.
# Note that some models (Qwen 3.5 in particular) get stupid without specifying the year of publication.
# Note that Qwen 2.5 Coder gets stuck in a loop on this prompt.
#PROMPT='Please summarize the book from Adam Smith published in 1776 - "Wealth of Nations" - in 3 paragraphs, and provide a list of the main points in bullet form.'

# Coding related prompt.
# Note that some models - sometimes! - get stuck in a loop on this prompt.
#PROMPT='Generate a Javascript program to compute Pi to 100 decimal places.'

# Hopefully this prompt is less likely to get stuck in a loop.
PROMPT='Generate a Javascript program to present a rotating cube in a web browser.'


model_download() {
    local model_key="${MODEL_KEY[$1]}"
    local model_family="${MODEL_FAMILY[$1]}"
    local model_name="${MODEL_NAME[$1]}"
    local model_spec="${MODEL_SPEC[$1]}"
    local model_options="${MODEL_OPTIONS[$model_key]}"
    echo "

==== Download 
MODEL_FAMILY    $model_family
MODEL_NAME      $model_name
MODEL_SPEC      $model_spec
"
    (
        set -x
        time llama-completion -hf "$model_name$model_spec" $model_options --jinja --single-turn --prompt "$PROMPT" || {
            echo "ERROR cannot download and run model $model_family -- $model_name"
            exit 1
        }
    )
}

model_benchmark() {
    local model_key="${MODEL_KEY[$1]}"
    local model_family="${MODEL_FAMILY[$1]}"
    local model_name="${MODEL_NAME[$1]}"
    local model_spec="${MODEL_SPEC[$1]}"
    local model_options="${MODEL_OPTIONS[$model_key]}"
    echo "

==== Benchmark
MODEL_FAMILY    $model_family
MODEL_NAME      $model_name
MODEL_SPEC      $model_spec
"

    # Run llama.cpp benchmark
    (
        set -x
        time llama-bench -hf "$model_name$model_spec" $model_options $OPTIONS_LLAMA_BENCH || {
            echo "ERROR cannot benchmark model $model_family -- $model_name"
            exit 1
        }
    )
}

{
    $WANT_DOWNLOAD && {
        for ((i=0; i<${#MODEL_NAME[@]}; i++)); do
            model_download $i
        done
    }

    $WANT_BENCHMARK && {
        for ((i=0; i<${#MODEL_NAME[@]}; i++)); do
            model_benchmark $i
        done
    }
} < /dev/null 2>&1 | tee "$FILE_LOG"

$WANT_SERVICE && {
    echo "Start: $SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME" 
}

echo "
==== Done
Done with model download / benchmarks. Logs in:
    $FILE_LOG
You can now install and run the server with:    
    sh install.sh
"
