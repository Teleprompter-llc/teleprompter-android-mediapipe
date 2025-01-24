load("//mediapipe/java/com/google/mediapipe:mediapipe_aar.bzl", "mediapipe_aar")
load(
    "//mediapipe/framework/tool:mediapipe_graph.bzl",
    "mediapipe_binary_graph",
)

mediapipe_binary_graph(
    name = "selfie_segmentation_bg_img_gpu_binary_graph",
    graph = "selfie_segmentation_bg_img_gpu.pbtxt",
    output_name = "selfie_segmentation_bg_img_gpu.binarypb",
    deps = ["//mediapipe/graphs/selfie_segmentation:selfie_segmentation_gpu_deps",],
)

mediapipe_binary_graph(
    name = "selfie_segmentation_gpu_binary_graph",
    graph = "selfie_segmentation_gpu.pbtxt",
    output_name = "selfie_segmentation_gpu.binarypb",
    deps = ["//mediapipe/graphs/selfie_segmentation:selfie_segmentation_gpu_deps",],
)

mediapipe_binary_graph(
    name = "selfie_segmentation_gpu_binary_graph_300",
    graph = "selfie_segmentation_gpu_300.pbtxt",
    output_name = "selfie_segmentation_gpu_300.binarypb",
    deps = ["//mediapipe/graphs/selfie_segmentation:selfie_segmentation_gpu_deps",],
)

mediapipe_binary_graph(
    name = "selfie_segmentation_gpu_binary_graph_600",
    graph = "selfie_segmentation_gpu_600.pbtxt",
    output_name = "selfie_segmentation_gpu_600.binarypb",
    deps = ["//mediapipe/graphs/selfie_segmentation:selfie_segmentation_gpu_deps",],
)

mediapipe_binary_graph(
    name = "selfie_segmentation_gpu_binary_graph_1200",
    graph = "selfie_segmentation_gpu_1200.pbtxt",
    output_name = "selfie_segmentation_gpu_1200.binarypb",
    deps = ["//mediapipe/graphs/selfie_segmentation:selfie_segmentation_gpu_deps",],
)


mediapipe_aar(
    name = "selfie_segmentation_gpu_aar",
    calculators = [
        "//mediapipe/calculators/core:flow_limiter_calculator",
        "//mediapipe/calculators/core:packet_cloner_calculator",
        "//mediapipe/calculators/image:recolor_calculator",
        "//mediapipe/calculators/image:image_transformation_calculator",
        "//mediapipe/calculators/image:mask_overlay_calculator",
        "//mediapipe/gpu:image_frame_to_gpu_buffer_calculator",
        "//mediapipe/graphs/selfie_segmentation:selfie_segmentation_gpu_deps",
    ],
)