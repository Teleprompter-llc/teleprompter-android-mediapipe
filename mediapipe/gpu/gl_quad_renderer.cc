// Copyright 2019 The MediaPipe Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "mediapipe/gpu/gl_quad_renderer.h"

static const GLchar* kTexturedFragmentShaderWithBlur = R"(
#ifdef GL_ES
precision mediump float;
#endif
uniform sampler2D video_frame;
uniform bool should_blur;
uniform float blur_size;
varying vec2 sample_coordinate;

void main() {
  if (should_blur) {
    float blurSize = 1.0 / blur_size;
    vec4 sum = vec4(0.0);
    float totalWeight = 0.0;
    
    // Sample in concentric circles rather than a grid
    int numRings = 8;      // Number of circular rings
    int samplesPerRing = 16;  // Samples per ring
    
    // Center pixel
    float centerWeight = 1.0;
    sum += texture2D(video_frame, sample_coordinate) * centerWeight;
    totalWeight += centerWeight;
    
    // Sample in concentric rings
    for(int ring = 1; ring <= numRings; ring++) {
        float radius = float(ring) * blurSize;
        float angleStep = 6.28318530718 / float(samplesPerRing); // 2*PI / samples
        
        for(int i = 0; i < samplesPerRing; i++) {
            float angle = float(i) * angleStep;
            vec2 offset = vec2(cos(angle), sin(angle)) * radius;
            
            float distance = length(offset);
            float weight = exp(-distance * distance * 3.0);
            
            sum += texture2D(video_frame, sample_coordinate + offset) * weight;
            totalWeight += weight;
        }
    }
    
    gl_FragColor = sum / totalWeight;
  } else {
    gl_FragColor = texture2D(video_frame, sample_coordinate);
  }
}
)";

#include "mediapipe/framework/port/ret_check.h"
#include "mediapipe/gpu/gl_simple_shaders.h"
#include "mediapipe/gpu/shader_util.h"

namespace mediapipe {

enum { ATTRIB_VERTEX, ATTRIB_TEXTURE_POSITION, NUM_ATTRIBUTES };

// static
FrameScaleMode FrameScaleModeFromProto(ScaleMode_Mode proto_scale_mode,
                                       FrameScaleMode default_mode) {
  switch (proto_scale_mode) {
    case ScaleMode_Mode_DEFAULT:
      return default_mode;
    case ScaleMode_Mode_STRETCH:
      return FrameScaleMode::kStretch;
    case ScaleMode_Mode_FIT:
      return FrameScaleMode::kFit;
    case ScaleMode_Mode_FILL_AND_CROP:
      return FrameScaleMode::kFillAndCrop;
    default:
      return default_mode;
  }
}

FrameRotation FrameRotationFromDegrees(int degrees_ccw) {
  switch (degrees_ccw) {
    case 0:
      return FrameRotation::kNone;
    case 90:
      return FrameRotation::k90;
    case 180:
      return FrameRotation::k180;
    case 270:
      return FrameRotation::k270;
    default:
      return FrameRotation::kNone;
  }
}

absl::Status QuadRenderer::GlSetup() {
  return GlSetup(kTexturedFragmentShaderWithBlur, {"video_frame"});
}

absl::Status QuadRenderer::GlSetup(
    const GLchar* custom_frag_shader,
    const std::vector<const GLchar*>& custom_frame_uniforms) {
  // Load vertex and fragment shaders
  const GLint attr_location[NUM_ATTRIBUTES] = {
      ATTRIB_VERTEX,
      ATTRIB_TEXTURE_POSITION,
  };
  const GLchar* attr_name[NUM_ATTRIBUTES] = {
      "position",
      "texture_coordinate",
  };

  GlhCreateProgram(kScaledVertexShader, custom_frag_shader, NUM_ATTRIBUTES,
                   &attr_name[0], attr_location, &program_);
  RET_CHECK(program_) << "Problem initializing the program.";

  frame_unifs_.resize(custom_frame_uniforms.size());
  for (int i = 0; i < custom_frame_uniforms.size(); ++i) {
    frame_unifs_[i] = glGetUniformLocation(program_, custom_frame_uniforms[i]);
    RET_CHECK(frame_unifs_[i] != -1)
        << "could not find uniform '" << custom_frame_uniforms[i] << "'";
  }
  scale_unif_ = glGetUniformLocation(program_, "scale");
  RET_CHECK(scale_unif_ != -1) << "could not find uniform 'scale'";
  
  should_blur_unif_ = glGetUniformLocation(program_, "should_blur");
  RET_CHECK(should_blur_unif_ != -1) << "could not find uniform 'should_blur'";
  
  blur_size_unif_ = glGetUniformLocation(program_, "blur_size");
  RET_CHECK(blur_size_unif_ != -1) << "could not find uniform 'blur_size'";

  glGenVertexArrays(1, &vao_);
  glGenBuffers(2, vbo_);

  glBindVertexArray(vao_);
  glEnableVertexAttribArray(ATTRIB_VERTEX);
  glEnableVertexAttribArray(ATTRIB_TEXTURE_POSITION);

  glBindBuffer(GL_ARRAY_BUFFER, vbo_[1]);
  glBufferData(GL_ARRAY_BUFFER, sizeof(mediapipe::kBasicTextureVertices),
               kBasicTextureVertices, GL_STATIC_DRAW);
  glVertexAttribPointer(ATTRIB_TEXTURE_POSITION, 2, GL_FLOAT, 0, 0, nullptr);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);

  return absl::OkStatus();
}

void QuadRenderer::GlTeardown() {
  if (program_) {
    glDeleteProgram(program_);
    program_ = 0;
  }
  if (vao_) {
    glDeleteVertexArrays(1, &vao_);
    vao_ = 0;
  }
  if (vbo_[0]) {
    glDeleteBuffers(2, vbo_);
    vbo_[0] = 0;
    vbo_[1] = 0;
  }
  rotation_ = std::nullopt;
}

absl::Status QuadRenderer::GlRender(float frame_width, float frame_height,
                                    float view_width, float view_height,
                                    FrameScaleMode scale_mode,
                                    FrameRotation rotation,
                                    bool flip_horizontal, bool flip_vertical,
                                    bool flip_texture, bool should_blur, float blur_size) const {
  RET_CHECK(program_) << "Must setup the program before rendering.";

  glUseProgram(program_);
  for (int i = 0; i < frame_unifs_.size(); ++i) {
    glUniform1i(frame_unifs_[i], i + 1);
  }
  glUniform1i(should_blur_unif_, should_blur ? 1 : 0);
  glUniform1f(blur_size_unif_, blur_size);

  // Determine scale parameter.
  if (rotation == FrameRotation::k90 || rotation == FrameRotation::k270) {
    std::swap(frame_width, frame_height);
  }
  GLfloat scale_width = frame_width / view_width;
  GLfloat scale_height = frame_height / view_height;
  GLfloat scale_adjust;

  switch (scale_mode) {
    case FrameScaleMode::kStretch:
      scale_width = scale_height = 1.0;
      break;
    case FrameScaleMode::kFillAndCrop:
      // Make the smallest dimension touch the edge.
      scale_adjust = std::min(scale_width, scale_height);
      scale_width /= scale_adjust;
      scale_height /= scale_adjust;
      break;
    case FrameScaleMode::kFit:
      // Make the largest dimension touch the edge.
      scale_adjust = std::max(scale_width, scale_height);
      scale_width /= scale_adjust;
      scale_height /= scale_adjust;
      break;
  }

  if (flip_texture) {
    switch (rotation) {
      case FrameRotation::kNone:  // Fall-through intended.
      case FrameRotation::k180:
        flip_vertical = !flip_vertical;
        break;
      case FrameRotation::k90:
        flip_horizontal = !flip_horizontal;
        break;
      case FrameRotation::k270:
        flip_horizontal = !flip_horizontal;
        break;
    }
  }
  const int h_flip_factor = flip_horizontal ? -1 : 1;
  const int v_flip_factor = flip_vertical ? -1 : 1;

  GLfloat scale[] = {scale_width * h_flip_factor, scale_height * v_flip_factor,
                     1.0, 1.0};
  glUniform4fv(scale_unif_, 1, scale);

  // Draw.

  glBindVertexArray(vao_);
  if (rotation != rotation_) {
    rotation_ = rotation;
    UpdateVertices(rotation);
  }

  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  glBindVertexArray(0);

  return absl::OkStatus();
}

void QuadRenderer::UpdateVertices(FrameRotation rotation) const {
  // Choose vertices for rotation.
  const GLfloat* vertices;  // quad used to render the texture.
  switch (rotation) {
    case FrameRotation::kNone:
      vertices = kBasicSquareVertices;
      break;
    case FrameRotation::k90:
      vertices = kBasicSquareVertices90;
      break;
    case FrameRotation::k180:
      vertices = kBasicSquareVertices180;
      break;
    case FrameRotation::k270:
      vertices = kBasicSquareVertices270;
      break;
  }

  glBindBuffer(GL_ARRAY_BUFFER, vbo_[0]);
  glBufferData(GL_ARRAY_BUFFER, sizeof(mediapipe::kBasicSquareVertices),
               vertices, GL_STATIC_DRAW);
  glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, nullptr);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
}

absl::Status FrameRotationFromInt(FrameRotation* rotation, int degrees_ccw) {
  RET_CHECK(degrees_ccw % 90 == 0) << "rotation must be a multiple of 90; "
                                   << degrees_ccw << " was provided";
  *rotation = FrameRotationFromDegrees(degrees_ccw % 360);
  return absl::OkStatus();
}

}  // namespace mediapipe
