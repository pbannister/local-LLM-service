#!/usr/bin/env bash

GPU=${GPU-"MI25"}

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

model_add() {
    local model_family="$1"
    local model_spec="$2"
    local model_name="$3"
    MODEL_FAMILY+=("$model_family")
    MODEL_SPEC+=("$model_spec")
    MODEL_NAME+=("$model_name")
}

# Selection of possibly-interesting models to download and benchmark.  
# These are all GGUF format models, which is the only format supported by llama.cpp for now.
# We are using the HuggingFace model spec format, which is <user>/<model-name>[:<quantization>].
# Models are downloaded into the HuggingFace cache, which is typically $HOME/.cache/huggingface/hub, 
# and then auto-discovered by llama.cpp when running benchmarks or the server.

model_add "DeepSeek_R1_Distill" ":Q4_K_M"   "unsloth/DeepSeek-R1-Distill-Qwen-7B-GGUF"

# model_add "Gemma"               ":Q4_K_M"   "MaziyarPanahi/gemma-7b-GGUF"

# Gemma 4 non-QAT GGUF crashes on MI25 (segfault). The QAT version below may work.
# model_add "Gemma_4"             ":Q4_K_M"   "unsloth/gemma-4-12b-it-GGUF"
# model_add "Gemma_4"             ":Q5_K_M"   "unsloth/gemma-4-12b-it-GGUF"
model_add "Gemma_4_QAT"         ":UD-Q4_K_XL" "unsloth/gemma-4-12B-it-qat-GGUF"

model_add "GPT-OSS"             ":Q4_K_M"   "unsloth/gpt-oss-20b-GGUF"   

# model_add "LLama_3.0"           ":Q4_K_M"   "MaziyarPanahi/Meta-Llama-3-8B-Instruct-GGUF"       
#model_add "LLama_3.1"           ":Q4_K_M"   "dphn/Dolphin3.0-Llama3.1-8B-GGUF"                  
# model_add "LLama_3.1"           ":Q4_K_M"   "NousResearch/Hermes-3-Llama-3.1-8B-GGUF"           
model_add "LLama_3.2"           ":Q4_K_M"   "bartowski/Llama-3.2-3B-Instruct-GGUF"              

# model_add "Microsoft_Phi-2"     ":Q4_K_M"   "TheBloke/phi-2-GGUF"                               
# model_add "Microsoft_Phi-3.5"   ":Q4_K_M"   "MaziyarPanahi/Phi-3.5-mini-instruct-GGUF"          
model_add "Microsoft_Phi-4"     ":Q4_K_M"   "unsloth/Phi-4-mini-instruct-GGUF"                  

model_add "Devtral_7B"          ":Q4_K_M"   "mistralai/Devstral-Small-2505_gguf"       
model_add "Mistral_7B"          ":Q4_K_M"   "MaziyarPanahi/Mistral-7B-Instruct-v0.3-GGUF"       

# model_add "Qwen_2.5_Coder"      ":Q4_K_M"   "lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF" 
# model_add "Qwen_2.5"            ":Q4_K_M"   "Qwen/Qwen2.5-7B-Instruct-GGUF"                     
model_add "Qwen_3.5"            ":Q4_K_M"   "unsloth/Qwen3.5-9B-GGUF"                           

# These do not generate meaningful results, so skip for now.
# model_add "GPT2"                ":Q8_0"   "PrunaAI/gpt2-GGUF-smashed"                         
# model_add "GPT2"                ":Q4_K_M" "QuantFactory/gpt2-GGUF"                            


OPTIONS_LLAMA_BENCH="
-p 512,2048,4096 
-n 128 
-ngl 99 
-r 3
"

PROMPT='Please summarize the book from Adam Smith - "Wealth of Nations" - in 3 paragraphs, and provide a list of the main points in bullet form.'

model_download() {
    local model_family="${MODEL_FAMILY[$1]}"
    local model_name="${MODEL_NAME[$1]}"
    local model_spec="${MODEL_SPEC[$1]}"
    echo "

==== Download 
MODEL_FAMILY    $model_family
MODEL_NAME      $model_name
MODEL_SPEC      $model_spec
"
    (
        set -x
        time llama-completion -hf "$model_name$model_spec" --single-turn --prompt "$PROMPT" || {
            echo "ERROR cannot download and run model $model_family -- $model_name"
            exit 1
        }
    )
}

model_benchmark() {
    local model_family="${MODEL_FAMILY[$1]}"
    local model_name="${MODEL_NAME[$1]}"
    local model_spec="${MODEL_SPEC[$1]}"

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

echo "
==== Done
Done with model download / benchmarks. Logs in:
    $FILE_LOG
You can now install and run the server with:    
    sh install.sh
"
