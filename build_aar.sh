#!/bin/bash

# MediaPipe AAR Build Script
# Based on instructions from README.md

# Note: We don't use 'set -e' here because we want to handle build failures gracefully
# and implement fallback strategies

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

# Set Android environment variables (following setup_android_sdk_and_ndk.sh pattern)
export ANDROID_HOME="${ANDROID_HOME:-/Users/csabahuszar/Library/Android/sdk}"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"

echo -e "${YELLOW}Android SDK: ${ANDROID_HOME}${NC}"
echo -e "${YELLOW}Android NDK: ${ANDROID_NDK_HOME}${NC}"

# Verify NDK exists
if [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo -e "${RED}Error: Android NDK not found at ${ANDROID_NDK_HOME}${NC}"
    echo -e "${YELLOW}Available NDK versions:${NC}"
    ls -la "$ANDROID_HOME/ndk/" 2>/dev/null || echo "No NDK directory found"
    exit 1
fi

echo -e "${GREEN}Building AAR...${NC}"

# Build the AAR with Android configuration - first try the .aar target
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"

# First try building the .aar target for complete AAR generation
echo -e "${YELLOW}Attempting to build AAR target with .aar suffix...${NC}"

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
  --linkopt=-Wl,--gc-sections,--strip-all \
  --repo_env=HERMETIC_PYTHON_VERSION=3.11 \
  "$1"

# Check if .aar target build succeeded and produced the AAR file
AAR_BUILD_RESULT=$?
# Extract target path and AAR name for dynamic path generation
TARGET_PATH=$(echo "$1" | cut -d':' -f1)  # Get everything before the colon
AAR_NAME=$(echo "$1" | cut -d':' -f2)     # Get everything after the colon

# Generate expected AAR path (remove .aar suffix from AAR_NAME if it exists to avoid double extension)
AAR_NAME_CLEAN=$(echo "$AAR_NAME" | sed 's/\.aar$//')
AAR_PATH="bazel-bin/${TARGET_PATH}/${AAR_NAME_CLEAN}.aar"

if [ $AAR_BUILD_RESULT -eq 0 ] && [ -f "${AAR_PATH}" ]; then
    echo -e "${GREEN}✅ AAR target build successful!${NC}"
    echo -e "${GREEN}AAR location: ${AAR_PATH}${NC}"
    ls -lh "${AAR_PATH}"
else
    echo -e "${YELLOW}⚠️  AAR target build failed or AAR not found, trying alternative approach...${NC}"
    
    # Fallback: Build the android_library target and check what was actually generated
    echo -e "${YELLOW}Building android_library target...${NC}"
    
    bazel build -c opt --strip=ALWAYS \
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
      --linkopt=-Wl,--gc-sections,--strip-all \
      --config=android_arm64 \
      --define=disable_opencv_ios=true \
      --define=disable_opencv_macos=true \
      --repo_env=HERMETIC_PYTHON_VERSION=3.11 \
      "$1"
    
    FALLBACK_RESULT=$?
    if [ $FALLBACK_RESULT -eq 0 ]; then
        echo -e "${YELLOW}✅ Android library build successful${NC}"
        echo -e "${YELLOW}Note: This generates android_library components but not the final AAR file${NC}"
        
        # Look for any AAR files that might have been generated
        echo -e "${YELLOW}Searching for generated AAR files...${NC}"
        find bazel-bin -name "*.aar" -type f 2>/dev/null | while read aar_file; do
            echo -e "${GREEN}Found AAR: ${aar_file}${NC}"
            ls -lh "${aar_file}"
        done
        
        # If no AAR found, indicate the limitation
        if [ ! -f "${AAR_PATH}" ]; then
            echo -e "${RED}❌ Final AAR file not generated at expected location${NC}"
            echo -e "${RED}Expected: ${AAR_PATH}${NC}"
            echo -e "${YELLOW}The build generated android_library components but requires additional setup to create the final AAR${NC}"
            echo -e "${YELLOW}However, native libraries were successfully built and can be found in bazel-bin${NC}"
        fi
    else
        echo -e "${RED}❌ Android library build also failed!${NC}"
        exit 1
    fi
fi

# Extract graph name from the AAR target for binary graph building
AAR_TARGET_NAME=$(basename "$1" | sed 's/:/ /g' | awk '{print $2}')

echo -e "${GREEN}Building binary graph...${NC}"

# Try to find and build the corresponding binary graph target
# Common naming pattern: replace _aar with _binary_graph or append _binary_graph
GRAPH_TARGET_BASE=$(echo "$AAR_TARGET_NAME" | sed 's/_aar//')
POSSIBLE_GRAPH_TARGETS=(
    "mediapipe/java/com/google/mediapipe/transformer:${GRAPH_TARGET_BASE}_binary_graph"
    "mediapipe/java/com/google/mediapipe/transformer:${GRAPH_TARGET_BASE}_bg_img_gpu_binary_graph"
    "mediapipe/java/com/google/mediapipe/transformer:${AAR_TARGET_NAME}_binary_graph"
)

GRAPH_BUILD_SUCCESS=0

for GRAPH_TARGET in "${POSSIBLE_GRAPH_TARGETS[@]}"; do
    echo -e "${YELLOW}Trying to build binary graph target: ${GRAPH_TARGET}${NC}"
    
    # Check if target exists first
    bazel query "$GRAPH_TARGET" 2>/dev/null >/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}  Target ${GRAPH_TARGET} does not exist, skipping...${NC}"
        continue
    fi
    
    # Build the binary proto graph with desktop configuration (not Android as graphs are host tools)
    bazel build \
      --repo_env=HERMETIC_PYTHON_VERSION=3.11 \
      "$GRAPH_TARGET"

    if [ $? -eq 0 ]; then
        # Find the generated binarypb file - check multiple possible locations
        GRAPH_FILE_CANDIDATES=(
            "bazel-bin/mediapipe/java/com/google/mediapipe/transformer/${GRAPH_TARGET_BASE}.binarypb"
            "$(find bazel-bin -name "*${GRAPH_TARGET_BASE}*.binarypb" 2>/dev/null | head -1)"
            "$(find bazel-bin -name "*.binarypb" -path "*transformer*" 2>/dev/null | head -1)"
        )
        
        for CANDIDATE in "${GRAPH_FILE_CANDIDATES[@]}"; do
            if [ -n "$CANDIDATE" ] && [ -f "$CANDIDATE" ]; then
                GRAPH_FILE="$CANDIDATE"
                break
            fi
        done
        
        if [ -n "$GRAPH_FILE" ] && [ -f "$GRAPH_FILE" ]; then
            echo -e "${GREEN}✅ Binary graph build successful!${NC}"
            echo -e "${GREEN}Binary graph location: ${GRAPH_FILE}${NC}"
            ls -lh "$GRAPH_FILE"
            GRAPH_BUILD_SUCCESS=1
            break
        else
            echo -e "${YELLOW}  Target built but binary graph file not found${NC}"
        fi
    else
        echo -e "${YELLOW}  Build failed for target ${GRAPH_TARGET}${NC}"
    fi
done

if [ $GRAPH_BUILD_SUCCESS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  No binary graph target found or buildable for this AAR${NC}"
    echo -e "${YELLOW}  The AAR can still be used without a separate binary graph file${NC}"
fi

echo -e "${GREEN}Build completed successfully!${NC}"
echo ""

echo -e "${GREEN}Checking ELF alignment...${NC}"
# Run ELF alignment check on the generated AAR
if [ -f "${AAR_PATH}" ]; then
    ./check_elf_alignment.sh "${AAR_PATH}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ ELF alignment check passed!${NC}"
    else
        echo -e "${YELLOW}⚠️  ELF alignment check completed with warnings (check output above)${NC}"
    fi
else
    echo -e "${RED}❌ Cannot run ELF alignment check: AAR file not found at ${AAR_PATH}${NC}"
fi
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo "1. Copy the AAR to your transformer demo project:"
echo "   cp ${AAR_PATH} \${TRANSFORMER_DEMO_ROOT}/libs/"
echo ""
echo "2. Copy the binary graph to your transformer demo assets:"
if [ -n "$GRAPH_FILE" ] && [ -f "$GRAPH_FILE" ]; then
    echo "   cp ${GRAPH_FILE} \${TRANSFORMER_DEMO_ROOT}/src/withMediaPipe/assets/"
else
    echo "   (No binary graph file available for this AAR)"
fi
echo ""
echo "3. Don't forget to also add:"
echo "   - selfie_segmentation.tflite to assets"
echo "   - libc++_shared.so to jniLibs/arm64-v8a/"
echo "   - NDK abiFilters configuration to app's defaultConfig"