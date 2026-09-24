#version 460 core
#include <flutter/runtime_effect.glsl>

// ImageFilter supplies the transparent COIN layer, never the page background.
uniform vec2 uSize;
uniform sampler2D uCoins;
out vec4 fragColor;

vec4 coinAt(vec2 uv) {
  vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
  return texture(uCoins, clamp(uv, vec2(0.0), vec2(1.0))) * inside.x * inside.y;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  #ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
  #endif
  vec2 radial = uv - vec2(0.5);
  // Elliptical vignette MASK: clear center, progressively refracted perimeter.
  // There is no colored vignette painted onto the background.
  float edge = smoothstep(0.70, 1.15, length(radial * 2.0));
  vec2 tangent = vec2(-radial.y, radial.x);
  // Sample outward so lens distortion pulls silhouettes inward, never into
  // the finite filter surface's edge. The previous inverse scale clipped them.
  vec2 warped = vec2(0.5) + radial * (1.0 + 0.035 * edge)
      + tangent * (0.012 * edge * edge);
  vec4 sharp = coinAt(warped);
  vec4 smear = vec4(0.0);
  float weights = 0.0;
  for (int i = 0; i < 24; i++) {
    float t = float(i) / 23.0;
    float weight = exp(-4.0 * t * t);
    smear += coinAt(warped + radial * t * 0.065 * edge) * weight;
    weights += weight;
  }
  vec4 color = mix(sharp, smear / weights, edge * 0.72);
  // Fine violet dispersion at the coin silhouette, preserving premultiplied alpha.
  vec4 fringe = coinAt(warped + radial * 0.007 * edge);
  vec4 violetFringe = vec4(fringe.a * vec3(0.54, 0.38, 0.86), fringe.a);
  fragColor = mix(color, violetFringe, edge * 0.07);
}
