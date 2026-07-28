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
                GPU_GB_FITS=64
                GPU="CPU"
            }
            /^Total:/ { 
                GPU_GB_FITS=$2
                CPU_GB_FITS=$2
            }
            { 
                sub(/^  Vulkan/,"") 
                sub(/:/,"") 
            } 
            /Radeon Instinct MI25/ { 
                DEVICE=$1
                GPU_GB_FITS=16
                GPU="MI25"
            }
            /Radeon RX 5500 XT/ { 
                DEVICE=$1
                GPU_GB_FITS=6 # (8 - 2) for other processes
                GPU="RX5500XT"
            }
            END {
                print DEVICE " " CPU_GB_FITS " " GPU_GB_FITS " " GPU
            }
        '
))

# Use the detected device as the default.
# Set GPU_GB_FITS to the maximum number of GB that can fit on your GPU.  
# This is used to filter out models that are too large to fit on your GPU.  

export GGML_VK_VISIBLE_DEVICES="${GGML_VK_VISIBLE_DEVICES-${DETECTED_DEVICES[0]}}"
CPU_GB_FITS=${CPU_GB_FITS-${DETECTED_DEVICES[1]}}
GPU_GB_FITS=${GPU_GB_FITS-${DETECTED_DEVICES[2]}}
GPU=${GPU-${DETECTED_DEVICES[3]}}

WANT_DOWNLOAD=${WANT_DOWNLOAD-true}
WANT_SMOKE=${WANT_SMOKE-true}
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

declare -A MODEL_OPTIONS_CONTEXT
declare -A MODEL_OPTIONS_HARDWARE
declare -A MODEL_OPTIONS_SAMPLING

model_key_this=""

model_fits() {
    local gb_wants_cpu="$1"
    local gb_wants_gpu="$2"
    [ "$CPU_GB_FITS" -lt "$gb_wants_cpu" ] && return 1
    [ "$GPU_GB_FITS" -lt "$gb_wants_gpu" ] && return 1
    return 0
}

model_family_add() {
    local model_family="$1"
    local model_spec="$2"
    local model_name="$3"
    model_key_this="$(echo $model_family | sha256sum | awk '{print $1}')"
    MODEL_KEY+=("$model_key_this")
    MODEL_FAMILY+=("$model_family")
    MODEL_SPEC+=("$model_spec")
    MODEL_NAME+=("$model_name")
    MODEL_OPTIONS_CONTEXT["$model_key_this"]=""
    MODEL_OPTIONS_HARDWARE["$model_key_this"]=""
    MODEL_OPTIONS_SAMPLING["$model_key_this"]=""
}

model_options_context() {
    MODEL_OPTIONS_CONTEXT["$model_key_this"]="$*"
}

model_options_hardware() {
    MODEL_OPTIONS_HARDWARE["$model_key_this"]="$*"
}

model_options_sampling() {
    MODEL_OPTIONS_SAMPLING["$model_key_this"]="$*"
}

WANT_MODELS=${WANT_MODELS-true}

WANT_MODELS_COMPLETION=${WANT_MODELS_COMPLETION-${WANT_MODELS}}
WANT_MODELS_REASONING=${WANT_MODELS_REASONING-${WANT_MODELS}}
WANT_MODELS_CPU=${WANT_MODELS_CPU-${WANT_MODELS}}

NUMA_FLAGS=""
case $( hostname ) in
beast)
    NUMA_FLAGS="--numa distribute"
    ;;
athena)
    ;;
esac

# Selection of possibly-interesting models to download and benchmark.  
# These are all GGUF format models, which is the only format supported by llama.cpp for now.
# We are using the HuggingFace model spec format, which is <user>/<model-name>[:<quantization>].
# Models are downloaded into the HuggingFace cache, which is typically $HOME/.cache/huggingface/hub, 
# and then auto-discovered by llama.cpp when running benchmarks or the server.

# Keep in mind the GB_WANTS values are guessed.

$WANT_MODELS_COMPLETION && {
    # =================================
    # Fast Code Completion (Deterministic low temp, 8k context cap to keep latency sub-10ms)
    # =================================

    model_fits 1 2 && {
        model_family_add "Qwen-2.5-Coder-1.5B" ":Q8_0" "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF"
        model_options_context "-c 8192"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.2 --top-p 0.95"
    }   
    model_fits 1 4 && {
        model_family_add "Qwen-2.5-Coder-3B" ":Q8_0" "Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
        model_options_context "-c 8192"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.2 --top-p 0.95"
    }

    # =================================
    # Fast Desktop Generalists
    # =================================

    model_fits 1 2 && {
        model_family_add "Llama-3.2-1B" ":Q8_0" "unsloth/Llama-3.2-1B-Instruct-GGUF"
        model_options_context "-c 8192"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.6 --top-p 0.9"
    }
    model_fits 1 4 && {
        model_family_add "Llama-3.2-3B" ":Q8_0" "unsloth/Llama-3.2-3B-Instruct-GGUF"
        model_options_context "-c 8192"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.6 --top-p 0.9"
    }

    # =================================
    # Fast IDE Chat
    # =================================

    model_fits 1 3 && {
        model_family_add "Gemma-4-E2B-QAT" ":UD-Q4_K_XL" "unsloth/gemma-4-E2B-it-qat-GGUF"         
        model_options_context "-c 8192"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.7"
    }
    model_fits 1 6 && {
        model_family_add "Gemma-4-E4B-QAT" ":UD-Q4_K_XL" "unsloth/gemma-4-E4B-it-qat-GGUF"          
        model_options_context "-c 8192"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.7"
    }
}

$WANT_MODELS_REASONING && {
    # =================================
    #   Agentic & Coding Workloads
    # =================================

    # Full GPU Offload (Fits completely in 16GB VRAM)
    model_fits 1 15 && {
        model_family_add "Devstral-Small-2-24B" ":Q4_K_M" "unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF"       
        model_options_context "-c 8192"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.15 --top-p 0.95"
    }

    # High-Speed MoE (Fits in 16GB VRAM because only 4B active parameters run per token)
    model_fits 1 15 && {
        model_family_add "Gemma-4-26B-A4B-QAT" ":UD-Q4_K_XL" "unsloth/gemma-4-26B-A4B-it-qat-GGUF"
        model_options_context "-c 16384"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.7"
    }

    # Full GPU Offload (~10GB VRAM)
    model_fits 1 10 && {
        model_family_add "DeepSeek-R1-Distill-Qwen-14B" ":Q4_K_M" "unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF"
        model_options_context "-c 16384"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.6 --top-p 0.95"
    }

    # Split GPU/CPU Workload (~14.2GB GPU VRAM + ~6GB System RAM)
    model_fits 8 14 && {
        model_family_add "Qwen-2.5-Coder-32B:GPU+CPU" ":Q4_K_M" "Qwen/Qwen2.5-Coder-32B-Instruct-GGUF"
        model_options_context "-c 16384"
        model_options_hardware "-ngl 46 $NUMA_FLAGS"
        model_options_sampling "--temp 0.2 --top-p 0.95"
    }

    # Split GPU/CPU Workload (~14.2GB GPU VRAM + ~6GB System RAM)
    # Similar to Qwen-2.5-Coder-32B
    false && model_fits 8 14 && {
        model_family_add "DeepSeek-R1-Distill-32B:GPU+CPU" ":Q4_K_M" "unsloth/DeepSeek-R1-Distill-Qwen-32B-GGUF"
        model_options_context "-c 16384"
        model_options_hardware "-ngl 46 $NUMA_FLAGS"
        model_options_sampling "--temp 0.6 --top-p 0.95"
    }

    # =================================
    # General Chat & Tool Calling
    # =================================

    # Full GPU Offload (~15GB VRAM)
    model_fits 1 15 && {
        model_family_add "GPT-OSS-20B" ":UD-Q4_K_XL" "unsloth/gpt-oss-20b-GGUF"   
        model_options_context "-c 16384"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.7"
    }
    model_fits 1 7 && {
        model_family_add "Gemma-4-12B-QAT" ":UD-Q4_K_XL" "unsloth/gemma-4-12B-it-qat-GGUF"          
        model_options_context "-c 16384"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.7"
    }
    model_fits 1 8 && {
        model_family_add "Mistral-Nemo-12B" ":Q4_K_M" "bartowski/Mistral-Nemo-Instruct-2407-GGUF"
        model_options_context "-c 16384"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.3"
    }

    # Full GPU Offload (~8GB VRAM)
    model_fits 1 8 && {
        model_family_add "Qwen-3.5-9B" ":Q4_K_M" "unsloth/Qwen3.5-9B-GGUF"                           
        model_options_context "-c 16384"
        model_options_hardware "-ngl 99"
        model_options_sampling "--temp 0.7 --top-p 0.8 --repeat-penalty 1.05"
        # Qwen 3.5 Models (Requires slight repeat penalty to prevent prompt loops)
    }

    # Split GPU/CPU Workload (~13.5GB GPU VRAM + ~3.5GB System RAM)
    model_fits 6 13 && {
        model_family_add "Qwen-3.5-27B:GPU+CPU" ":Q4_K_M" "unsloth/Qwen3.5-27B-GGUF"                           
        model_options_context "-c 16384"
        model_options_hardware "-ngl 50 $NUMA_FLAGS"
        model_options_sampling "--temp 0.7 --top-p 0.8 --repeat-penalty 1.05"
        # Qwen 3.5 Models (Requires slight repeat penalty to prevent prompt loops)
    }
}

$WANT_MODELS_CPU && {
    # =================================
    # Heavyweight CPU Workloads (Requires NUMA distribution across dual Xeon sockets)
    # =================================

    model_fits 80 0 && {
        model_family_add "GPT-OSS-120B:CPU" ":UD-Q4_K_XL" "unsloth/gpt-oss-120b-GGUF"
        model_options_context "-c 16384"
        model_options_hardware "-ngl 0 $NUMA_FLAGS"
        model_options_sampling "--temp 0.7"
    }
    model_fits 48 0 && {
        model_family_add "Llama-3.3-70B:CPU" ":UD-Q4_K_XL" "unsloth/Llama-3.3-70B-Instruct-GGUF"
        model_options_context "-c 16384"
        model_options_hardware "-ngl 0 $NUMA_FLAGS"
        model_options_sampling "--temp 0.6 --top-p 0.9"
    }
    model_fits 48 0 && {
        model_family_add "DeepSeek-R1-Distill-70B:CPU" ":UD-Q4_K_XL" "unsloth/DeepSeek-R1-Distill-Llama-70B-GGUF"
        model_options_context "-c 16384"
        model_options_hardware "-ngl 0 $NUMA_FLAGS"
        model_options_sampling "--temp 0.6 --top-p 0.95"
    }

    # =================================
    # Lightweight CPU Workloads (Requires NUMA distribution across dual Xeon sockets)
    # =================================

    model_fits 4 0 && {
        model_family_add "Gemma-4-E2B-QAT:CPU" ":UD-Q4_K_XL" "unsloth/gemma-4-E2B-it-qat-GGUF"         
        model_options_context "-c 8192"
        model_options_hardware "-ngl 0 $NUMA_FLAGS"
        model_options_sampling "--temp 0.7"
    }
    model_fits 2 0 && {
        model_family_add "Gemma-4-E4B-QAT:CPU" ":UD-Q4_K_XL" "unsloth/gemma-4-E4B-it-qat-GGUF"         
        model_options_context "-c 8192"
        model_options_hardware "-ngl 0 $NUMA_FLAGS"
        model_options_sampling "--temp 0.7"
    }
}

OPTIONS_LLAMA_COMPLETION="
--jinja 
--single-turn
"

OPTIONS_LLAMA_BENCH="
-p 512,2048,4096 
-n 128 
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
    
    # Strip leading colon from spec for file matching
    local pattern="*${model_spec#:}*"
    echo "

==== Download
MODEL_FAMILY    $model_family
MODEL_NAME      $model_name
MODEL_SPEC      $model_spec
"

    (
        # Echo each full download command so we see exact parameters.
        set -x
        time hf download "$model_name" --include "$pattern"
    ) || {
        echo "ERROR cannot download model $model_family -- $model_name"
        exit 1
    }
}

model_smoke() {
    local model_key="${MODEL_KEY[$1]}"
    local model_family="${MODEL_FAMILY[$1]}"
    local model_name="${MODEL_NAME[$1]}"
    local model_spec="${MODEL_SPEC[$1]}"
    local model_options="${MODEL_OPTIONS_CONTEXT[$model_key]} ${MODEL_OPTIONS_HARDWARE[$model_key]} ${MODEL_OPTIONS_SAMPLING[$model_key]}"
    echo "

==== Smoke test 
MODEL_FAMILY    $model_family
MODEL_NAME      $model_name
MODEL_SPEC      $model_spec
"
    (
        set -x
        time llama-completion -hf "$model_name$model_spec" $OPTIONS_LLAMA_COMPLETION $model_options --prompt "$PROMPT"
    ) || {
        echo "ERROR cannot run model $model_family -- $model_name"
        exit 1
    }
    echo "==== DONE: $model_family"
}

model_benchmark() {
    local model_key="${MODEL_KEY[$1]}"
    local model_family="${MODEL_FAMILY[$1]}"
    local model_name="${MODEL_NAME[$1]}"
    local model_spec="${MODEL_SPEC[$1]}"
    local model_options="${MODEL_OPTIONS_HARDWARE[$model_key]}"
    echo "

==== Benchmark
MODEL_FAMILY    $model_family
MODEL_NAME      $model_name
MODEL_SPEC      $model_spec
"

    # Run llama.cpp benchmark
    (
        set -x
        time llama-bench -hf "$model_name$model_spec" $OPTIONS_LLAMA_BENCH $model_options
    ) || {
        echo "ERROR cannot benchmark model $model_family -- $model_name"
        exit 1
    }
    echo "==== DONE: $model_family"
}

{
    $WANT_DOWNLOAD && {
        for ((i=0; i<${#MODEL_NAME[@]}; i++)); do
            model_download $i
        done
    }
    $WANT_SMOKE && {
        for ((i=0; i<${#MODEL_NAME[@]}; i++)); do
            model_smoke $i
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
