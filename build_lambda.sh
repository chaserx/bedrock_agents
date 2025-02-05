#!/bin/bash

# Export requirements
uv export --frozen --no-dev --no-editable -o requirements.txt

# Install dependencies
uv pip install \
    --no-installer-metadata \
    --no-compile-bytecode \
    --python-platform x86_64-manylinux2014 \
    --python 3.13 \
    --target packages \
    -r requirements.txt

# Create zip with dependencies
cd packages && zip -r ../fake_telematics.zip . && cd ..

# Add source code and data to zip
zip -r fake_telematics.zip src requirements.txt
