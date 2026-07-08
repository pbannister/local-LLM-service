# Local LLM 

Wanted to run LLMs (Large Language Models) on my local subnet.
Did not want to send data to the cloud.
Did not want to buy tokens, and incur unknown expense.
The easy route would be to buy a well-supported high-end GPU, but did not want to spend that sort of money.

A few years back, bought an old datacenter GPU (AMD Instinct MI25).
As this particular GPU is trouble to use, the card is inexpensive.
With 16GB of memory, this GPU is not small, and not the largest.

Wanted to offer a service on my local subnet, with a selection of models.
Once running ... found this works rather well.

What follows is a setup particular to my purpose.
You might want something different.

## The Service - llama.cpp

The main trick to get the MI25 working is to use **llama.cpp** compiled to use the **Vulcan** backend.
(Ask an LLM how. Perhaps not Microsoft Copilot.)

| file              | purpose   |
| ----              | ----      |
| **install.sh**    | Sets up a **systemd** service to run **llama.cpp** in "router" mode.  |
| **config.ini**    | Contains the **llama.cpp** server configuration.                      |
 
Note I am allowing *unsecured* connections (as my local subnet is secure).
Again, this is specific to my purpose.

On my local subnet, I can now connect a web browser to ``beast.lan:2001``.
The web UI of **llama.cpp** is rather nice.

## Benchmarks

Aim was to benchmark a set of LLMs (Large Language Models) suitable for an **AMD Instinct MI25**.
The script downloads the LLMs (as needed) and runs benchmarks. 

### Usage

First, determine what devices are seen by Vulcan.
```sh
$ llama-cli --list-devices
Available devices:
  Vulkan0: NVIDIA GeForce GTX 1050 (2294 MiB, 1950 MiB free)
  Vulkan1: AMD Radeon Instinct MI25 (RADV VEGA10) (16368 MiB, 16343 MiB free)
```

Force Vulcan to use only the GPU we want to benchmark.
```sh
$ GGML_VK_VISIBLE_DEVICES=1 bash download-mi25-models.sh 
```

### Models

The **MI25** GPU has 16GB of memory, so models were selected to fit. 

Models used are stored in the HuggingFace cache.

| Model Family | Model Name |
| ----         | ----       |
| DeepSeek_R1_Distill | unsloth/DeepSeek-R1-Distill-Qwen-7B-GGUF:Q4_K_M |
| Gemma_4_QAT | unsloth/gemma-4-12B-it-qat-GGUF:UD-Q4_K_XL |
| GPT-OSS | unsloth/gpt-oss-20b-GGUF:Q4_K_M |
| LLama_3.2 | bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M |
| Microsoft_Phi-4 | unsloth/Phi-4-mini-instruct-GGUF:Q4_K_M |
| Devtral_7B | mistralai/Devstral-Small-2505_gguf:Q4_K_M |
| Mistral_7B | MaziyarPanahi/Mistral-7B-Instruct-v0.3-GGUF:Q4_K_M |
| Qwen_3.5 | unsloth/Qwen3.5-9B-GGUF:Q4_K_M |

### llama-bench

Options given to **llama-bench**:

| option    | description                                                                       |
| ----      | ----                                                                              |
| -n 128    | Generates 128 consecutive sequential tokens to evaluate memory bus speed.         |
| -ngl 99   | Forces maximum structural layer offloading directly to GPU VRAM hardware.         |
| -r 3      | Samples each evaluation tier three distinct times to calculate exact deviation.   |

Note that **llama-bench** outputs results in Markdown format.
Output from the run can be used almost directly.

Also output from individual benchmarks are stored in: ``${MODEL_HOME}/benchmark_${model_name}.txt``

