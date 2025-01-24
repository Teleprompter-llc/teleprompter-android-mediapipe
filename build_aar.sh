#!/bin/bash

# MediaPipe AAR Build Script
# Based on instructions from README.md

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}MediaPipe AAR Build Script${NC}"
echo "==============================="

# Check if we're in the MediaPipe root directory
if [ ! -f "WORKSPACE" ]; then
    echo -e "${RED}Error: WORKSPACE file not found. Please run this script from the MediaPipe root directory.${NC}"
    exit 1
fi

# Set MediaPipe root
MEDIAPIPE_ROOT="$(pwd)"
echo -e "${YELLOW}MediaPipe root: ${MEDIAPIPE_ROOT}${NC}"

# Set Python version
export HERMETIC_PYTHON_VERSION=3.11
echo -e "${YELLOW}Using Python version: ${HERMETIC_PYTHON_VERSION}${NC}"

echo -e "${GREEN}Building AAR...${NC}"

# Build the AAR
bazel build -c opt --strip=ALWAYS \
  --host_crosstool_top=@bazel_tools//tools/cpp:toolchain \
  --fat_apk_cpu=arm64-v8a,armeabi-v7a \
  --legacy_whole_archive=0 \
  --features=-legacy_whole_archive \
  --copt=-fvisibility=hidden \
  --copt=-ffunction-sections \
  --copt=-fdata-sections \
  --copt=-fstack-protector \
  --copt=-Oz \
  --copt=-fomit-frame-pointer \
  --copt=-DABSL_MIN_LOG_LEVEL=2 \
  --linkopt=-Wl,--gc-sections \
  mediapipe/java/com/google/mediapipe/transformer:selfie_segmentation_gpu_aar.aar

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ AAR build successful!${NC}"
    
    # Check if AAR exists
    AAR_PATH="bazel-bin/mediapipe/java/com/google/mediapipe/transformer/selfie_segmentation_gpu_aar.aar"
    if [ -f "${AAR_PATH}" ]; then
        echo -e "${GREEN}AAR location: ${AAR_PATH}${NC}"
        ls -lh "${AAR_PATH}"
    else
        echo -e "${RED}Warning: AAR file not found at expected location${NC}"
    fi
else
    echo -e "${RED}❌ AAR build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Building binary graph...${NC}"

# Build the binary proto graph
bazel build mediapipe/java/com/google/mediapipe/transformer:selfie_segmentation_gpu_binary_graph

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Binary graph build successful!${NC}"
    
    # Check if binary graph exists
    BINARY_GRAPH_PATH="bazel-bin/mediapipe/java/com/google/mediapipe/transformer/selfie_segmentation_gpu.binarypb"
    if [ -f "${BINARY_GRAPH_PATH}" ]; then
        echo -e "${GREEN}Binary graph location: ${BINARY_GRAPH_PATH}${NC}"
        ls -lh "${BINARY_GRAPH_PATH}"
    else
        echo -e "${RED}Warning: Binary graph file not found at expected location${NC}"
    fi
else
    echo -e "${RED}❌ Binary graph build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Build completed successfully!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Copy the AAR to your transformer demo project:"
echo "   cp ${AAR_PATH} \${TRANSFORMER_DEMO_ROOT}/libs/"
echo ""
echo "2. Copy the binary graph to your transformer demo assets:"
echo "   cp ${BINARY_GRAPH_PATH} \${TRANSFORMER_DEMO_ROOT}/src/withMediaPipe/assets/"
echo ""
echo "3. Don't forget to also add:"
echo "   - selfie_segmentation.tflite to assets"
echo "   - libc++_shared.so to jniLibs/arm64-v8a/"
echo "   - NDK abiFilters configuration to app's defaultConfig"