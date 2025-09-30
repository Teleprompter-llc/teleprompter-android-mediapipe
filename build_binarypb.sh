#!/bin/bash

# Script to build all binary graph targets from mediapipe/java/com/google/mediapipe/transformer/BUILD

set -e

echo "Building all binary graph targets..."
echo ""

targets=(
    "selfie_segmentation_bg_img_gpu_binary_graph"
    "selfie_segmentation_gpu_binary_graph"
    "selfie_segmentation_gpu_binary_graph_300"
    "selfie_segmentation_gpu_binary_graph_600"
    "selfie_segmentation_gpu_binary_graph_1200"
)

for target in "${targets[@]}"; do
    echo "Building target: $target"
    bazel build "mediapipe/java/com/google/mediapipe/transformer:$target"
    echo ""
done

echo "All binary graph targets built successfully!"
