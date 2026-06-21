# Local LLM Provisioning & Benchmarking Suite

The aim here is to benchmark a set of LLMs (Large Language Models) suitable for an **AMD Instinct MI25**.
The script downloads the LLMs (as needed) and runs benchmarks. 

## Usage

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

## Models

The **MI25** GPU has 16GB of memory, so models were selected to fit. 

Models are stored under ``$MODEL_HOME`` (the "$HOME/models" directory). 

| Index | Model Name                | Model File                            | Folder Path                   |
| ----  | ----                      | ----                                  | ----                          | 
| 0     | Mistral 7B Instruct v0.2  | mistral-7b-instruct-v0.2.Q4_K_M.gguf  | $MODEL_HOME/mistral-7b        | 
| 1     | Llama 3 8B Instruct       | Meta-Llama-3-8B-Instruct-Q4_K_M.gguf  | $MODEL_HOME/llama3-8b         | 
| 2     | Qwen 2.5 7B Instruct      | (Multi-File Shard) 00001 & 00002      | $MODEL_HOME/qwen2.5-7b        |
| 3     | Qwen 2.5 Coder 7B         | (Multi-File Shard) 00001 & 00002      | $MODEL_HOME/qwen2.5-coder-7b  | 
| 4     | Gemma 4 12B IT            | gemma-4-12b-it-Q4_K_M.gguf            | $MODEL_HOME/gemma-4-12b       | 
| 5     | GPT-OSS 20B               | gpt-oss-20b-Q4_K_M.gguf               | $MODEL_HOME/gpt-oss-20b2      |

## llama-bench

Options given to **llama-bench**:

| option    | description                                                                       |
| ----      | ----                                                                              |
| -n 128    | Generates 128 consecutive sequential tokens to evaluate memory bus speed.         |
| -ngl 99   | Forces maximum structural layer offloading directly to GPU VRAM hardware.         |
| -r 3      | Samples each evaluation tier three distinct times to calculate exact deviation.   |

Note that **llama-bench** outputs results in Markdown format.
Output from the run can be used almost directly.

Output from individual benchmarks are stored in: ``$MODEL_HOME/benchmark_${model_name}.txt``

