#!/bin/sh

FROM=/home/${USER}/.cache/huggingface
INTO=/backups/huggingface

mkdir -p "${INTO}"
rsync -av "${FROM}/." "${INTO}/."

du -sh $FROM $INTO
