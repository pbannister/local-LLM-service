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

MODEL_KEY=()
MODEL_FAMILY=()
MODEL_NAME=()
MODEL_SPEC=()

declare -A MODEL_OPTIONS

model_key_last=""

model_add() {
    local gb_wants="$1"
    [ "$GB_FITS" -lt "$gb_wants" ] && return 0
    local model_family="$2"
    local model_spec="$3"
    local model_name="$4"
    model_key_last="$(echo $model_family | sha256sum | awk '{print $1}')"
    MODEL_KEY+=("$model_key_last")
    MODEL_FAMILY+=("$model_family")
    MODEL_SPEC+=("$model_spec")
    MODEL_NAME+=("$model_name")
}

model_options() {
    local model_key="$model_key_last"
    local model_options="$0"
    MODEL_OPTIONS["$model_key"]="$model_options"
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
    model_add  2    "DeepSeek-R1-Distill-Qwen-1.5B"     ":UD-Q4_K_XL"   "unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
    model_add 10    "DeepSeek-R1-Distill-Qwen-14B"      ":Q4_K_M"       "unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF"
}

$WANT_MODELS_GEMMA4 && {
    # Gemma 4 non-QAT GGUF crashes on MI25 (segfault). The QAT version below may work.

    # Efficient Architecture (E2B and E4B): 
    # The "E" stands for "effective" parameters. 
    # The smaller models incorporate Per-Layer Embeddings (PLE) to maximize parameter efficiency in on-device deployments. 
    # Rather than adding more layers to the model, PLE gives each decoder layer its own small embedding for every token. 
    # These embedding tables are large but only used for quick lookups, 
    # which is why the total memory required to load static weights is higher than the effective parameter count suggests.

    model_add  3    "Gemma-4-E2B-QAT"                   ":UD-Q4_K_XL"   "unsloth/gemma-4-E2B-it-qat-GGUF"         
    model_options       "--jinja"
    model_add  5    "Gemma-4-E4B-QAT"                   ":UD-Q4_K_XL"   "unsloth/gemma-4-E4B-it-qat-GGUF"         
    model_options       "--jinja"

    # The MoE Architecture (26B A4B): 
    # The 26B is a Mixture of Experts model. 
    # While it only activates 4 billion parameters per token during generation, 
    # all 26 billion parameters must be loaded into memory to maintain fast routing and inference speeds. 
    # This is why its baseline memory requirement is much closer to a dense 26B model than a 4B model.

    model_add 15    "Gemma-4-26B-A4B-QAT"               ":UD-Q4_K_XL"   "unsloth/gemma-4-26B-A4B-it-qat-GGUF"         
    model_options       "--jinja"
    
    model_add  7    "Gemma-4-12B-QAT"                   ":UD-Q4_K_XL"   "unsloth/gemma-4-12B-it-qat-GGUF"          
    model_options       "--jinja"
    model_add 18    "Gemma-4-31B-QAT"                   ":UD-Q4_K_XL"   "unsloth/gemma-4-31B-it-qat-GGUF"          
    model_options       "--jinja"
}
$WANT_MODELS_GEMMA4 && {
    # GGUF exports of josephmayo/gemma-4-E4B-it-Coder, a merged coding-focused fine-tune of google/gemma-4-E4B-it.
    model_add  6    "Gemma-4-E4B-Coder"                 ":Q5_K_M"       "josephmayo/gemma-4-E4B-it-Coder-GGUF"          
    model_options       "--jinja"
}
$WANT_MODELS_GEMMA4 && {
    # Gemma4-12B v2 — Coding + Agentic Edition
    # Tiny footprint, big brain — a local coding & tool-using agent for everyone
    # Big agentic upgrade — reads, reasons, uses tools, and works through multi-step technical tasks. 
    # llama cli -hf yuxinlu1/gemma-4-12B-agentic-fable5-composer2.5-v2-3.5x-tau2-GGUF:Q4_K_M
    model_add 6     "Gemma-4-12B-agentic"               ":Q4_K_M"       "yuxinlu1/gemma-4-12B-agentic-fable5-composer2.5-v2-3.5x-tau2-GGUF"         
    model_options       "--jinja --temp 1.0 --top-p 0.95 --top-k 64"
}


$WANT_MODELS_GPT && {
    model_add  7    "GPT-OSS-7B"                        ":Q4_K_M"       "unsloth/gpt-oss-7b-GGUF"    
    model_add 15    "GPT-OSS-20B"                       ":Q4_K_M"       "unsloth/gpt-oss-20b-GGUF"   

    # Split model to fit 8GB VRAM, by pushing the layers to CPU. (untested)  
    model_add  7    "GPT-OSS-20B-split"                 ":Q4_K_M"       "unsloth/gpt-oss-20b-GGUF"                      
    model_options       "--n-cpu-moe 32"
}

$WANT_MODELS_LLAMA && {
    model_add  1    "LLama-3.2-1B"                      ":Q4_K_M"       "unsloth/Llama-3.2-1B-Instruct-GGUF"              
    model_add  3    "LLama-3.2-3B"                      ":Q4_K_M"       "unsloth/Llama-3.2-3B-Instruct-GGUF"              
}

$WANT_MODELS_MISTRAL && {
    model_add 16    "Mistral-Small-3.2-24B"             ":Q4_K_S"       "unsloth/Mistral-Small-3.2-24B-Instruct-2506-GGUF"       
    model_add 16    "Devstral-Small-2-24B"              ":Q4_K_M"       "unsloth/Devstral-Small-2-24B-Instruct-2512-GGUF"       
}

# Seems smaller models are faster. and Qwen2.5-Coder supports code-completion (FIN?).
# Taken together, you might want to load whatever model will fit in your local GPU for code-completion tasks.  

$WANT_MODELS_QWEN && {
    model_add  2    "Qwen-2.5-Coder-1.5B"               ":Q4_K_M"       "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF"
    model_add  3    "Qwen-2.5-Coder-3B"                 ":Q4_K_M"       "Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
    model_add  7    "Qwen-2.5-Coder-7B"                 ":Q4_K_M"       "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF"
}
$WANT_MODELS_QWEN && {
    model_add  2    "Qwen-3.5-2B"                       ":Q4_K_M"       "unsloth/Qwen3.5-2B-GGUF"   
    model_options       "--temp 0.7 --top-p 0.95"
    model_add  4    "Qwen-3.5-4B"                       ":Q4_K_M"       "unsloth/Qwen3.5-4B-GGUF"      
    model_options       "--temp 0.7 --top-p 0.95"

    # Found article recommending this model for 8GB VRAM.
    model_add  8    "Qwen-3.5-9B"                       ":Q4_K_M"       "unsloth/Qwen3.5-9B-GGUF"                           
    model_options       "--temp 0.7 --top-p 0.95"
    
    model_add 18    "Qwen-3.5-27B"                      ":Q4_K_S"       "unsloth/Qwen3.5-27B-GGUF"                           
    model_options       "--temp 0.7 --top-p 0.95"
}
$WANT_MODELS_QWEN && {
    # Variant with large (1M) context window.
    # Gets stuck in a loop on the smoke test. Reported to Qwythos devs. 
    #model_add 10 "Qwythos-9B-Claude-Mythos-5-1M"    ":Q4_K_M"       "empero-ai/Qwythos-9B-Claude-Mythos-5-1M-GGUF"

    # Updated model published after above report.
    # llama cli -hf empero-ai/Qwythos-9B-v2-GGUF:Q4_K_M
    model_add 10 "Qwythos-9B-v2"                    ":Q4_K_M"       "empero-ai/Qwythos-9B-v2-GGUF"
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
        time llama-completion -hf "$model_name$model_spec" --single-turn --prompt "$PROMPT" $model_options || {
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
        time llama-bench $OPTIONS_LLAMA_BENCH -hf "$model_name$model_spec" $model_options || {
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
