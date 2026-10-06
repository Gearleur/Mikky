
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../theme.dart';
import '../ui/tokens.dart';

/// His arms, still (2026-10-06: « pour l'instant ne fais pas d'animation,
/// juste des keyframes »; the arms are animated once these are right):
/// the plump ones (« on garde que la version dodus »), in four poses. Raised, an arm
/// turns from where it grows, a little bigger; it never slides up.
abstract final class ArmPoses {
  static Choreography _pose(String name, Map<String, double> values) => Choreography(
        name: name,
        duration: 1,
        tracks: {for (final e in values.entries) e.key: [Beat(0, e.value)]},
      );

  static final all = [
    _pose('Au repos', {'arms': 1, 'armLeftLift': -.15, 'armRightLift': -.15}),
    _pose('Coucou', {'arms': 1, 'armLeftLift': -.15, 'armRightLift': .95, 'armRightGrow': .5, 'happy': 1, 'tilt': -.08}),
    _pose('Montre', {'arms': 1, 'armLeftLift': -.15, 'armRightLift': .12, 'armRightGrow': .85, 'yaw': .5}),
    _pose('Youpi', {'arms': 1, 'armLeftLift': .85, 'armRightLift': .85, 'armLeftGrow': .4, 'armRightGrow': .4, 'happy': 1}),
  ];
}

/// Mikky's pose at [t] in [c].
MikkyPose poseAt(Choreography c, double t) {
  final pose = MikkyPose();
  for (final prop in MikkyProp.values) {
    if (c.tracks.containsKey(prop.name)) pose[prop] = c.value(prop.name, t);
  }
  return pose;
}

/// Mikky as [c] has him at [t], with radius [r].
MikkyGeometry geometryAt(Choreography c, double t, double r) {
  final furball = c.value('furball', t);
  final eyes = c.value('happy', t) > .5
      ? EyeShape.happy
      : c.value('closed', t) > .5
          ? EyeShape.closed
          : EyeShape.oval;
  return MikkyGeometry.posed(
    poseAt(c, t),
    r,
    time: t,
    eyeLeft: eyes,
    eyeRight: eyes,
    form: furball.abs() > .001 ? MikkyForm.furball : MikkyForm.cat,
    morph: furball,
  );
}

/// Mikky alone, in a pose (his arms).
class PoseScene extends StatelessWidget {
  const PoseScene(this.choreography, this.t, {super.key, this.size = const Size(240, 150), this.radius = 34});

  final Choreography choreography;
  final double t;
  final Size size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final mui = MikkyUi.of(context);
    final theme = mui.isLight ? MikkyTheme.light : MikkyTheme.dark;
    return Container(
      width: size.width,
      height: size.height,
      color: mui.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708),
      child: CustomPaint(painter: _PosePainter(choreography, t, theme, radius)),
    );
  }
}

class _PosePainter extends CustomPainter {
  _PosePainter(this.c, this.t, this.theme, this.radius);

  final Choreography c;
  final double t;
  final MikkyTheme theme;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    MikkyPainter(
      geometry: geometryAt(c, t, radius),
      // `y` moves him (units of his radius): his hops.
      center: Offset(size.width / 2, size.height * .58 + c.value('y', t) * radius),
      rim: theme.mikkyRim,
      statusColor: theme.status,
      foreground: theme.foreground,
      showBadge: false,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_PosePainter old) => old.t != t || old.c != c || old.theme != theme || old.radius != radius;
}
