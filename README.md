# Summary

To implement background blur, I've edited the selfie segmentation graph:
mediapipe/graphs/selfie_segmentation/selfie_segmentation_gpu.pbtxt

and BUILD file:
mediapipe/graphs/selfie_segmentation/BUILD

and used them in the transformer project to build the aar:
mediapipe/java/com/google/mediapipe/transformer/BUILD
mediapipe/java/com/google/mediapipe/transformer/selfie_segmentation_gpu.pbtxt


# How to build

Building the demo app with [MediaPipe][] integration enabled requires some extra
manual steps.

1.  Follow the
    [instructions](https://google.github.io/mediapipe/getting_started/install.html)
    to install MediaPipe.
1.  Do not forget to add your sdk and ndk path to the WORKSPACE files
1.  Copy the Transformer demo's build configuration and MediaPipe graph text
    protocol buffer under the MediaPipe source tree. This makes it easy to
    [build an AAR][] with bazel by reusing MediaPipe's workspace.

    ```sh
    cd "<path to teleprompter-android-MediaPipe checkout>"
    MEDIAPIPE_ROOT="$(pwd)"
    MEDIAPIPE_TRANSFORMER_ROOT="${MEDIAPIPE_ROOT}/mediapipe/java/com/google/mediapipe/transformer"
    cd "<path to the transformer demo (/teleprompter-android-media/demos/transformer/)>"
    TRANSFORMER_DEMO_ROOT="$(pwd)"
    mkdir -p "${TRANSFORMER_DEMO_ROOT}/libs"
    ```

1.  Build the AAR and the binary proto for the demo's MediaPipe graph, then copy
    them to Transformer.

    ```sh
    cd ${MEDIAPIPE_ROOT}
    export HERMETIC_PYTHON_VERSION=3.11
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
      mediapipe/java/com/google/mediapipe/transformer:selfie_segmentation_gpu_aar.aar
    cp bazel-bin/mediapipe/java/com/google/mediapipe/transformer/selfie_segmentation_gpu_aar.aar \
      ${TRANSFORMER_DEMO_ROOT}/libs
    bazel build mediapipe/java/com/google/mediapipe/transformer:selfie_segmentation_gpu_binary_graph
    cp bazel-bin/mediapipe/java/com/google/mediapipe/transformer/selfie_segmentation_gpu.binarypb \
      ${TRANSFORMER_DEMO_ROOT}/src/withMediaPipe/assets
    ```

    Also don't forget to put selfie_segmentation.tflite to ${TRANSFORMER_DEMO_ROOT}/src/withMediaPipe/assets
    libc++_shared.so must be added to the project at jniLibs/arm64-v8a/libc++_shared.so path.

    Also add this:
    ```
  ndk {
            // Specify the ABI configurations you want to build
            abiFilters 'arm64-v8a'
        }
    ```
    to the app's defaultConfig

1.  In Android Studio, gradle sync and select the `withMediaPipe` build variant
    (this will only appear if the AAR is present), then build and run the demo
    app and select a MediaPipe-based effect.

[Transformer]: https://developer.android.com/media/media3/transformer
[MediaPipe]: https://google.github.io/mediapipe/
[build an AAR]: https://google.github.io/mediapipe/getting_started/android_archive_library.html

# 16KB Page Size Support

## Google Play Requirement

**Important:** Starting **November 1st, 2025**, all new apps and updates to existing apps submitted to Google Play targeting Android 15 (API level 35) and higher **must support 16 KB page sizes on 64-bit devices**.

## Why 16KB Page Size?

Historically, Android has only supported 4 KB memory page sizes. Beginning with Android 15, AOSP supports devices configured to use 16 KB page sizes. As device manufacturers build devices with larger amounts of physical memory (RAM), many will adopt 16 KB page sizes to optimize device performance.

### Performance Benefits

Devices configured with 16 KB page sizes gain various performance improvements:

- **3.16% lower app launch times** under memory pressure (up to 30% for some apps)
- **4.56% reduction in power draw** during app launch
- **4.48% faster camera hot starts** (6.60% faster cold starts)
- **8% improved system boot time** (~950ms faster on average)

## Building MediaPipe with 16KB Support

### Prerequisites

To build with 16 KB page size support, you need:

- **Android NDK r28+** (automatically builds with 16 KB alignment)
- **Android Gradle Plugin 8.5.1+**
- **Gradle 8.4+**
- **Target SDK 35+**

### Updated Build Command

When building the MediaPipe AAR, add the 16 KB alignment linker flag:

```sh
cd ${MEDIAPIPE_ROOT}
export HERMETIC_PYTHON_VERSION=3.11
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
  --linkopt='-Wl,-z,max-page-size=16384' \
  mediapipe/java/com/google/mediapipe/transformer:selfie_segmentation_gpu_aar.aar
```

**Note:** The key addition is `--linkopt='-Wl,-z,max-page-size=16384'` which ensures 16 KB alignment.

### MediaPipe 16KB Updates

MediaPipe has been updated to support 16 KB page sizes natively. The project now uses Android SDK and NDK 28, which builds with 16 KB alignment by default. See the [MediaPipe 16KB update commit](https://github.com/google-ai-edge/mediapipe/commit/6795b5ce0762eb9238a22a6ec392f0ba95f2b485) for implementation details.

## TensorFlow Lite Compatibility

If your project uses TensorFlow Lite, be aware that TensorFlow Lite 2.17.0's pre-built native libraries are compiled with 4 KB page size alignment. The recommended solution is to migrate to **LiteRT (formerly TensorFlow Lite) version 1.4.0+**, which provides native 16 KB page size compatibility.

## Testing Your App for 16KB Compatibility

### Verify APK Alignment

After building your app, verify it's 16 KB-aligned:

```sh
zipalign -c -P 16 -v 4 your_app.apk
```

### Test on 16KB Environment

Verify your test device is using 16 KB pages:

```sh
adb shell getconf PAGE_SIZE
# Should return: 16384
```

### Android Emulator Setup

1. Use **Android Studio Ladybug | 2024.2.1+** for the best experience
2. In **Tools > SDK Manager > SDK Platforms**, check **Show Package Details**
3. Expand **Android VanillaIceCream** or higher and download:
   - **Google APIs Experimental 16 KB Page Size ARM 64 v8a System Image**
   - **Google APIs Experimental 16 KB Page Size Intel x86_64 Atom System Image**
4. Create a new AVD using one of these 16 KB system images

### Physical Device Testing

Enable **"Boot with 16KB page size"** in Developer Options on supported devices:

- **Pixel 8, 8 Pro, 8a** (Android 15 QPR1+)
- **Pixel 9, 9 Pro, 9 Pro XL** (Android 15 QPR2 Beta 2+)

### Check Native Libraries

Use APK Analyzer in Android Studio to identify native libraries:

1. **File > Open** any project
2. **Build > Analyze APK...**
3. Check the **lib** folder for `.so` files
4. Review the **Alignment** column for warnings

For command-line verification of shared object files:

```sh
# Linux/macOS
$SDK_ROOT/Android/sdk/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-objdump -p libname.so | grep LOAD

# Check for alignment value 0x4000 (16KB) instead of 0x1000 (4KB)
```

## Additional Resources

- [Android Developer Guide: Support 16 KB Page Sizes](https://developer.android.com/guide/practices/page-sizes)
- [TensorFlow Lite and 16 KB Page Size Support Discussion](https://discuss.ai.google.dev/t/tensorflow-lite-and-16-kb-page-size-support/93052/3)
- [FFmpeg Kit 16 KB Page Size Implementation](https://proandroiddev.com/ffmpeg-kit-16-kb-page-size-in-android-d522adc5efa2)
- [Android NDK r28 Release Builds](https://ci.android.com/builds/branches/aosp-ndk-r28-release/grid?legacy=1)
- [MediaPipe 16 KB Support Commit](https://github.com/google-ai-edge/mediapipe/commit/6795b5ce0762eb9238a22a6ec392f0ba95f2b485)

---
layout: forward
target: https://developers.google.com/mediapipe
title: Home
nav_order: 1
---

----

**Attention:** *We have moved to
[https://developers.google.com/mediapipe](https://developers.google.com/mediapipe)
as the primary developer documentation site for MediaPipe as of April 3, 2023.*

![MediaPipe](https://developers.google.com/static/mediapipe/images/home/hero_01_1920.png)

**Attention**: MediaPipe Solutions Preview is an early release. [Learn
more](https://developers.google.com/mediapipe/solutions/about#notice).

**On-device machine learning for everyone**

Delight your customers with innovative machine learning features. MediaPipe
contains everything that you need to customize and deploy to mobile (Android,
iOS), web, desktop, edge devices, and IoT, effortlessly.

*   [See demos](https://goo.gle/mediapipe-studio)
*   [Learn more](https://developers.google.com/mediapipe/solutions)

## Get started

You can get started with MediaPipe Solutions by by checking out any of the
developer guides for
[vision](https://developers.google.com/mediapipe/solutions/vision/object_detector),
[text](https://developers.google.com/mediapipe/solutions/text/text_classifier),
and
[audio](https://developers.google.com/mediapipe/solutions/audio/audio_classifier)
tasks. If you need help setting up a development environment for use with
MediaPipe Tasks, check out the setup guides for
[Android](https://developers.google.com/mediapipe/solutions/setup_android), [web
apps](https://developers.google.com/mediapipe/solutions/setup_web), and
[Python](https://developers.google.com/mediapipe/solutions/setup_python).

## Solutions

MediaPipe Solutions provides a suite of libraries and tools for you to quickly
apply artificial intelligence (AI) and machine learning (ML) techniques in your
applications. You can plug these solutions into your applications immediately,
customize them to your needs, and use them across multiple development
platforms. MediaPipe Solutions is part of the MediaPipe [open source
project](https://github.com/google/mediapipe), so you can further customize the
solutions code to meet your application needs.

These libraries and resources provide the core functionality for each MediaPipe
Solution:

*   **MediaPipe Tasks**: Cross-platform APIs and libraries for deploying
    solutions. [Learn
    more](https://developers.google.com/mediapipe/solutions/tasks).
*   **MediaPipe models**: Pre-trained, ready-to-run models for use with each
    solution.

These tools let you customize and evaluate solutions:

*   **MediaPipe Model Maker**: Customize models for solutions with your data.
    [Learn more](https://developers.google.com/mediapipe/solutions/model_maker).
*   **MediaPipe Studio**: Visualize, evaluate, and benchmark solutions in your
    browser. [Learn
    more](https://developers.google.com/mediapipe/solutions/studio).

### Legacy solutions

We have ended support for [these MediaPipe Legacy Solutions](https://developers.google.com/mediapipe/solutions/guide#legacy)
as of March 1, 2023. All other MediaPipe Legacy Solutions will be upgraded to
a new MediaPipe Solution. See the [Solutions guide](https://developers.google.com/mediapipe/solutions/guide#legacy)
for details. The [code repository](https://github.com/google/mediapipe/tree/master/mediapipe)
and prebuilt binaries for all MediaPipe Legacy Solutions will continue to be
provided on an as-is basis.

For more on the legacy solutions, see the [documentation](https://github.com/google/mediapipe/tree/master/docs/solutions).

## Framework

To start using MediaPipe Framework, [install MediaPipe
Framework](https://developers.google.com/mediapipe/framework/getting_started/install)
and start building example applications in C++, Android, and iOS.

[MediaPipe Framework](https://developers.google.com/mediapipe/framework) is the
low-level component used to build efficient on-device machine learning
pipelines, similar to the premade MediaPipe Solutions.

Before using MediaPipe Framework, familiarize yourself with the following key
[Framework
concepts](https://developers.google.com/mediapipe/framework/framework_concepts/overview.md):

*   [Packets](https://developers.google.com/mediapipe/framework/framework_concepts/packets.md)
*   [Graphs](https://developers.google.com/mediapipe/framework/framework_concepts/graphs.md)
*   [Calculators](https://developers.google.com/mediapipe/framework/framework_concepts/calculators.md)

## Community

*   [Slack community](https://mediapipe.page.link/joinslack) for MediaPipe
    users.
*   [Discuss](https://groups.google.com/forum/#!forum/mediapipe) - General
    community discussion around MediaPipe.
*   [Awesome MediaPipe](https://mediapipe.page.link/awesome-mediapipe) - A
    curated list of awesome MediaPipe related frameworks, libraries and
    software.

## Contributing

We welcome contributions. Please follow these
[guidelines](https://github.com/google/mediapipe/blob/master/CONTRIBUTING.md).

We use GitHub issues for tracking requests and bugs. Please post questions to
the MediaPipe Stack Overflow with a `mediapipe` tag.

## Resources

### Publications

*   [Bringing artworks to life with AR](https://developers.googleblog.com/2021/07/bringing-artworks-to-life-with-ar.html)
    in Google Developers Blog
*   [Prosthesis control via Mirru App using MediaPipe hand tracking](https://developers.googleblog.com/2021/05/control-your-mirru-prosthesis-with-mediapipe-hand-tracking.html)
    in Google Developers Blog
*   [SignAll SDK: Sign language interface using MediaPipe is now available for
    developers](https://developers.googleblog.com/2021/04/signall-sdk-sign-language-interface-using-mediapipe-now-available.html)
    in Google Developers Blog
*   [MediaPipe Holistic - Simultaneous Face, Hand and Pose Prediction, on
    Device](https://ai.googleblog.com/2020/12/mediapipe-holistic-simultaneous-face.html)
    in Google AI Blog
*   [Background Features in Google Meet, Powered by Web ML](https://ai.googleblog.com/2020/10/background-features-in-google-meet.html)
    in Google AI Blog
*   [MediaPipe 3D Face Transform](https://developers.googleblog.com/2020/09/mediapipe-3d-face-transform.html)
    in Google Developers Blog
*   [Instant Motion Tracking With MediaPipe](https://developers.googleblog.com/2020/08/instant-motion-tracking-with-mediapipe.html)
    in Google Developers Blog
*   [BlazePose - On-device Real-time Body Pose Tracking](https://ai.googleblog.com/2020/08/on-device-real-time-body-pose-tracking.html)
    in Google AI Blog
*   [MediaPipe Iris: Real-time Eye Tracking and Depth Estimation](https://ai.googleblog.com/2020/08/mediapipe-iris-real-time-iris-tracking.html)
    in Google AI Blog
*   [MediaPipe KNIFT: Template-based feature matching](https://developers.googleblog.com/2020/04/mediapipe-knift-template-based-feature-matching.html)
    in Google Developers Blog
*   [Alfred Camera: Smart camera features using MediaPipe](https://developers.googleblog.com/2020/03/alfred-camera-smart-camera-features-using-mediapipe.html)
    in Google Developers Blog
*   [Real-Time 3D Object Detection on Mobile Devices with MediaPipe](https://ai.googleblog.com/2020/03/real-time-3d-object-detection-on-mobile.html)
    in Google AI Blog
*   [AutoFlip: An Open Source Framework for Intelligent Video Reframing](https://ai.googleblog.com/2020/02/autoflip-open-source-framework-for.html)
    in Google AI Blog
*   [MediaPipe on the Web](https://developers.googleblog.com/2020/01/mediapipe-on-web.html)
    in Google Developers Blog
*   [Object Detection and Tracking using MediaPipe](https://developers.googleblog.com/2019/12/object-detection-and-tracking-using-mediapipe.html)
    in Google Developers Blog
*   [On-Device, Real-Time Hand Tracking with MediaPipe](https://ai.googleblog.com/2019/08/on-device-real-time-hand-tracking-with.html)
    in Google AI Blog
*   [MediaPipe: A Framework for Building Perception Pipelines](https://arxiv.org/abs/1906.08172)

### Videos

*   [YouTube Channel](https://www.youtube.com/c/MediaPipe)
