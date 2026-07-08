#!/usr/bin/env bash

SERVICE_NAME=${SERVICE_NAME-"llama.service"}
LISTEN_ADDRESS=${LISTEN_ADDRESS-0.0.0.0}
LISTEN_PORT=${LISTEN_PORT-2001}
MODELS_MAX=${MODELS_MAX-4}

HF_HUB_CACHE=${HF_HUB_CACHE-/home/${USER}/.cache/huggingface/hub}

MODEL_HOME="$HOME/models"
test -d "$MODEL_HOME" || {
    echo "ERROR: cannot find model directory: $MODEL_HOME"
    echo "Please run download-mi25-models.sh first to download the models into $MODEL_HOME"
    exit 1
}

DETECTED_DEVICES="$( 
    llama-cli --list-devices | 
        awk '
            /AMD.*MI25 /{ 
                sub(/^ *Vulkan/,"")
                sub(/:.*$/,"")
                print 
            }' 
)"

GGML_VK_VISIBLE_DEVICES=${GGML_VK_VISIBLE_DEVICES-${DETECTED_DEVICES}}

# Create and configure the systemd unit file
cat <<XXXX | sudo tee /etc/systemd/system/${SERVICE_NAME}
[Unit]
Description=Llama.cpp Multi-Model Subnet Server
After=network.target

[Service]
Type=simple
User=${USER}
Group=${USER}

# Set standard cache variables just in case llama-server evaluates them internally
Environment="HF_HUB_CACHE=${HF_HUB_CACHE}"

# Force llama-server to use the MI25 (GPU 1) for all models.
Environment="GGML_VK_VISIBLE_DEVICES=${GGML_VK_VISIBLE_DEVICES}"

# Set the working directory to the model home
WorkingDirectory=${MODEL_HOME}

# Make sure the absolute path to your compiled llama-server is correct
ExecStart=/usr/local/bin/llama-server \
    --models-preset ${MODEL_HOME}/config.ini \
    --host ${LISTEN_ADDRESS} \
    --port ${LISTEN_PORT} \
    --models-max ${MODELS_MAX} \
    --fit on \
    --fit-target 1024 \
    --tools all

Restart=on-failure
RestartSec=5

# System profiling protections
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
XXXX

# Initialize and launch the service 
sudo systemctl daemon-reload
sudo systemctl stop ${SERVICE_NAME}
sudo systemctl enable --now ${SERVICE_NAME}
sudo systemctl status ${SERVICE_NAME}
