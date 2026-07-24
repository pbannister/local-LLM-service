#!/usr/bin/env bash

WANT_SERVICE=${WANT_SERVICE-true}

SERVICE_NAME="llama.service"
$WANT_SERVICE && {
    echo "Stop: $SERVICE_NAME"
    sudo systemctl stop "$SERVICE_NAME" 
}

GPU=${GPU-"MI25"}

# Set GB_FITS to the maximum number of GB that can fit on your GPU.  This is used to filter out models that are too large to fit on your GPU.  The default is 16GB, which is the maximum for MI25.  You can override this by setting the GB_FITS environment variable before running this script.
GB_FITS=${GB_FITS-16}

# Detect MI25 devices and set GGML_VK_VISIBLE_DEVICES to the list of detected devices.

DETECTED_DEVICES="$( 
    llama-cli --list-devices | 
        awk '
            /AMD.*MI25 /{ 
                sub(/^ *Vulkan/,"")
                sub(/:.*$/,"")
                print 
            }' 
)"

export GGML_VK_VISIBLE_DEVICES="${GGML_VK_VISIBLE_DEVICES-${DETECTED_DEVICES}}"

WANT_DOWNLOAD=${WANT_DOWNLOAD-true}
WANT_BENCHMARK=${WANT_BENCHMARK-true}

MODEL_HOME="$HOME/models"
mkdir -p "$MODEL_HOME"

LOGS_BASE="$MODEL_HOME/logs"
mkdir -p "$LOGS_BASE"

WHEN=$(date +%Y-%m-%d-%H-%M)
FILE_LOG="$LOGS_BASE/run-$GPU-$WHEN.log"

MODEL_FAMILY=()
MODEL_NAME=()
MODEL_SPEC=()
MODEL_OPTIONS=()

model_add() {
    local gb_wants="$1"
    [ "$GB_FITS" -lt "$gb_wants" ] && return 0
    local model_family="$2"
    local model_spec="$3"
    local model_name="$4"
    local model_options="$5"
    MODEL_FAMILY+=("$model_family")
    MODEL_SPEC+=("$model_spec")
    MODEL_NAME+=("$model_name")
    MODEL_OPTIONS+=("$model_options")
}

WANT_MODELS=${WANT_MODELS-true}
WANT_MODELS_DEEPSEEK=${WANT_MODELS_DEEPSEEK-${WANT_MODELS}}
WANT_MODELS_GEMMA4=${WANT_MODELS_GEMMA4-${WANT_MODELS}}
WANT_MODELS_GPT=${WANT_MODELS_GPT-${WANT_MODELS}}
WANT_MODELS_LLAMA=${WANT_MODELS_LLAMA-${WANT_MODELS}}
WANT_MODELS_MISTRAL=${WANT_MODELS_MISTRAL-${WANT_MODELS}}
WANT_MODELS_QWEN=${WANT_MODELS_QWEN-${WANT_MODELS}}

# Selection of possibly-interesting models to download and benchmark.  
# These are all GGUF format models, which is the only format supported by llama.cpp for now.
# We are using the HuggingFace model spec format, which is <user>/<model-name>[:<quantization>].
# Models are downloaded into the HuggingFace cache, which is typically $HOME/.cache/huggingface/hub, 
# and then auto-discovered by llama.cpp when running benchmarks or the server.

# Keep in mind the GB_WANTS values are guessed.

$WANT_MODELS_DEEPSEEK && {
    model_add 2  "DeepSeek-R1-Distill-Qwen-1.5B"   ":UD-Q4_K_XL"   "unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
    model_add 10 "DeepSeek-R1-Distill-Qwen-14B"    ":Q4_K_M"       "unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF"
}

$WANT_MODELS_GEMMA4 && {
    # Gemma 4 non-QAT GGUF crashes on MI25 (segfault). The QAT version below may work.
    model_add 4  "Gemma-4-E2B-QAT"                 ":UD-Q4_K_XL"   "unsloth/gemma-4-E2B-it-qat-GGUF"                 "--jinja"
    model_add 8  "Gemma-4-E4B-QAT"                 ":UD-Q4_K_XL"   "unsloth/gemma-4-E4B-it-qat-GGUF"                 "--jinja"
    model_add 8  "Gemma-4-12B-QAT"                 ":UD-Q4_K_XL"   "unsloth/gemma-4-12B-it-qat-GGUF"                 "--jinja"
    model_add 16 "Gemma-4-26B-A4B-QAT"             ":UD-Q4_K_XL"   "unsloth/gemma-4-26B-A4B-it-qat-GGUF"             "--jinja"
    model_add 18 "Gemma-4-31B-QAT"                 ":UD-Q4_K_XL"   "unsloth/gemma-4-31B-it-qat-GGUF"                 "--jinja"
}

$WANT_MODELS_GPT && {
    model_add 7  "GPT-OSS-7B"                      ":Q4_K_M"       "unsloth/gpt-oss-7b-GGUF"    
    model_add 16 "GPT-OSS-20B"                     ":Q4_K_M"       "unsloth/gpt-oss-20b-GGUF"   
}

$WANT_MODELS_LLAMA && {
    model_add 1  "LLama-3.2-1B"                    ":Q4_K_M"       "unsloth/Llama-3.2-1B-Instruct-GGUF"              
    model_add 3  "LLama-3.2-3B"                    ":Q4_K_M"       "unsloth/Llama-3.2-3B-Instruct-GGUF"              
}

$WANT_MODELS_MISTRAL && {
    model_add 16 "Mistral-Small-3.2-24B"           ":Q4_K_S"       "unsloth/Mistral-Small-3.2-24B-Instruct-2506-GGUF"       
    model_add 16 "Devstral-Small-2-24B"            ":Q4_K_M"       "unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF"       
}

# Seems smaller models are faster. and Qwen2.5-Coder supports code-completion (FIN?).
# Taken together, you might want to load whatever model will fit in your local GPU for code-completion tasks.  

$WANT_MODELS_QWEN && {
    model_add 2  "Qwen-2.5-Coder-1.5B"             ":Q4_K_M"       "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF"
    model_add 3  "Qwen-2.5-Coder-3B"               ":Q4_K_M"       "Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
    model_add 7  "Qwen-2.5-Coder-7B"               ":Q4_K_M"       "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF"
}
$WANT_MODELS_QWEN && {
    model_add 2  "Qwen-3.5-2B"                     ":Q4_K_M"       "unsloth/Qwen3.5-2B-GGUF"                           
    model_add 4  "Qwen-3.5-4B"                     ":Q4_K_M"       "unsloth/Qwen3.5-4B-GGUF"                           
    model_add 8  "Qwen-3.5-9B"                     ":Q4_K_M"       "unsloth/Qwen3.5-9B-GGUF"                           
    model_add 18 "Qwen-3.5-27B"                    ":Q4_K_S"       "unsloth/Qwen3.5-27B-GGUF"                           
}
false && {
    # Variant with large (1M) context window.
    model_add 10 "Qwythos-9B-Claude-Mythos-5-1M"   ":Q4_K_M"       "empero-ai/Qwythos-9B-Claude-Mythos-5-1M-GGUF"
    # Gets stuck in a loop on the smoke test.
}

OPTIONS_LLAMA_BENCH="
-p 512,2048,4096 
-n 128 
-ngl 99 
-r 3
"

# Note that some models (Qwen 3.5 in particular) get stupid without specifying the year of publication.
# Note that Qwen 2.5 Coder gets stuck in a loop on this prompt.
PROMPT='Please summarize the book from Adam Smith published in 1776 - "Wealth of Nations" - in 3 paragraphs, and provide a list of the main points in bullet form.'

# Coding related prompt.
PROMPT='Generate a Javascript program to compute Pi to 100 decimal places.'



model_download() {
    local model_family="${MODEL_FAMILY[$1]}"
    local model_name="${MODEL_NAME[$1]}"
    local model_spec="${MODEL_SPEC[$1]}"
    local model_options="${MODEL_OPTIONS[$1]}"
    echo "

==== Download 
MODEL_FAMILY    $model_family
MODEL_NAME      $model_name
MODEL_SPEC      $model_spec
"
    (
        set -x
        time llama-completion -hf "$model_name$model_spec" --single-turn --prompt "$PROMPT" $model_options || {
            echo "ERROR cannot download and run model $model_family -- $model_name"
            exit 1
        }
    )
}

model_benchmark() {
    local model_family="${MODEL_FAMILY[$1]}"
    local model_name="${MODEL_NAME[$1]}"
    local model_spec="${MODEL_SPEC[$1]}"
    # local model_options="${MODEL_OPTIONS[$1]}"
    echo "

==== Benchmark
MODEL_FAMILY    $model_family
MODEL_NAME      $model_name
MODEL_SPEC      $model_spec
"

    # Run llama.cpp benchmark
    (
        set -x
        time llama-bench $OPTIONS_LLAMA_BENCH -hf "$model_name$model_spec" || {
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
