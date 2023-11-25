#!/bin/bash
python3 user-watch.py &
python3 webui.py --listen --xformers --enable-insecure-extension-access --disable-nan-check --api