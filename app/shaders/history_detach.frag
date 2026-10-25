#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec4 uBody;
uniform vec4 uRail;
uniform float uBodyRadius;
uniform float uRailRadius;
uniform float uK;
uniform vec4 uBodyColor;
uniform vec4 uRailColor;
uniform float uPx;

out vec4 fragColor;

#include "island_shape.glsl"

void main() {
  vec2 p = FlutterFragCoord().xy;
  float body = sdRoundedBox(p - uBody.xy, uBody.zw, uBodyRadius, 2.);
  float rail = sdRoundedBox(p - uRail.xy, uRail.zw, uRailRadius, 2.);
  // A tall rail separates at its ends first. The remaining liquid join
  // stays around its centre, like the island's round split bubble.
  float joinY = (p.y - uRail.y) / 24.;
  float k = 1. + (uK - 1.) * exp(-joinY * joinY);
  float d = smin(body, rail, k);
  // The white history keeps its colour while the grey rail emerges.
  float railMix = clamp(.5 + .5 * (body - rail) / k, 0., 1.) *
      (1. - smoothstep(uBody.x - uBody.z - 4., uBody.x - uBody.z + 8., p.x));
  vec4 fill = mix(uBodyColor, uRailColor, railMix);
  float a = clamp(.5 - d / uPx, 0., 1.) * fill.a;
  fragColor = vec4(fill.rgb * a, a);
}
