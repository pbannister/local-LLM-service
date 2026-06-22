#!/usr/bin/env bash

MODEL_HOME="$HOME/models"
test -d "$MODEL_HOME" || {
    echo "ERROR: cannot find model directory: $MODEL_HOME"
    echo "Please run download-mi25-models.sh first to download the models into $MODEL_HOME"
    exit 1
}

# Create and configure the systemd unit file
cat <<XXXX | sudo tee /etc/systemd/system/llama.service
[Unit]
Description=Llama.cpp Multi-Model Subnet Server
After=network.target

[Service]
Type=simple
User=preston
Group=preston

# Set standard cache variables just in case llama-server evaluates them internally
Environment="HF_HUB_CACHE=/home/preston/.cache/huggingface/hub"

# Force llama-server to use the MI25 (GPU 1) for all models.
Environment="GGML_VK_VISIBLE_DEVICES=1"

# Make sure the absolute path to your compiled llama-server is correct
ExecStart=/usr/local/bin/llama-server \
    --models-preset $MODEL_HOME/config.ini \
    --host 0.0.0.0 \
    --port 2001 \
    --models-max 4 \
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
sudo systemctl stop llama.service
sudo systemctl enable --now llama.service
sudo systemctl status llama.service
