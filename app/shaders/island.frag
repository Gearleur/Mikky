#version 460 core

// Mikky's island, ported from design/prototypes/ile-noir-et-blanc.html
// (modes 0 "noir A" and 6 "blanc pur"). Continuous-corner box (power-4
// norm), merged by smooth-min with the notification drop and the split
// bubble, two-layer shadow. All lengths are logical pixels, y down.
//
// Output is premultiplied: the island over its own shadow, over a fully
// transparent window, so the shadow darkens whatever is on the desktop.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec4 uBox;    // center x, center y, half width, half height
uniform float uR;     // corner radius
uniform vec3 uDrop;   // notification drop: x, y, radius
uniform vec3 uSide;   // split bubble: x, y, radius
uniform float uK;     // smooth-min size with the drop
uniform float uKs;    // smooth-min size with the bubble
uniform float uLight; // 0: dark "A", 1: light "pur"
uniform float uPx;    // one physical pixel, in logical pixels
uniform float uVis;   // global visibility, 0 when hidden

out vec4 fragColor;

float len4(vec2 v) {
  v = v * v;
  return pow(dot(v, v), .25);
}

float sdBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return len4(max(q, 0.)) + min(max(q.x, q.y), 0.) - r;
}

float smin(float a, float b, float k) {
  float h = clamp(.5 + .5 * (b - a) / k, 0., 1.);
  return mix(b, a, h) - k * h * (1. - h);
}

float scene(vec2 p) {
  float d = sdBox(p - uBox.xy, uBox.zw, uR);
  d = smin(d, length(p - uDrop.xy) - uDrop.z, uK);
  d = smin(d, length(p - uSide.xy) - uSide.z, uKs);
  return d;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float d = scene(p);
  vec2 e = vec2(uPx, 0.);
  vec2 n = normalize(vec2(scene(p + e.xy) - scene(p - e.xy), scene(p + e.yx) - scene(p - e.yx)) + 1e-6);
  float outside = smoothstep(-uPx, uPx, d);

  // Two-layer shadow: wide and soft, then tight contact.
  float wide = mix(.38, .13, uLight) *
      exp(-max(scene(p - vec2(0., mix(10., 14., uLight))), 0.) / mix(20., 30., uLight)) * outside;
  float contact = mix(.20, .10, uLight) *
      exp(-max(scene(p - vec2(0., mix(2., 1., uLight))), 0.) / mix(3., 2., uLight)) * outside;
  float shadow = 1. - (1. - wide) * (1. - contact);

  vec3 fill;
  if (uLight < .5) {
    // Near-black, 1.3 px inner rim (brighter at the bottom), faint inner glow.
    float rim = 1. - smoothstep(0., 1.3, -d);
    fill = vec3(.028, .028, .032) + rim * (.13 + .10 * max(0., n.y)) + .025 * (1. - smoothstep(0., 40., -d));
  } else {
    // Opaque white with a half-point edge.
    fill = vec3(1.) - .085 * (1. - smoothstep(0., .9, -d));
  }

  float a = clamp(.5 - d / uPx, 0., 1.);
  fragColor = vec4(fill * a, a + (1. - a) * shadow) * uVis;
}
