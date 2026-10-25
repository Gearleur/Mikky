// Shared by the island's split bubble and the history's detached rail.
float sdRoundedBox(vec2 p, vec2 b, float r, float power) {
  vec2 q = abs(p) - b + r;
  vec2 v = max(q, 0.);
  float rounded = pow(pow(v.x, power) + pow(v.y, power), 1. / power);
  return rounded + min(max(q.x, q.y), 0.) - r;
}

float smin(float a, float b, float k) {
  float h = clamp(.5 + .5 * (b - a) / k, 0., 1.);
  return mix(b, a, h) - k * h * (1. - h);
}
