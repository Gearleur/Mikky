import '../theme.dart';

/// One fake agent of the demo scene.
class DemoAgent {
  const DemoAgent({
    required this.name,
    required this.color,
    required this.activity,
    required this.time,
    this.progress,
    this.waiting = false,
  });

  final String name;
  final StatusColor color;

  /// What it is doing now, shown in mono.
  final String activity;
  final String time;

  /// 0..1 for agents at work.
  final double? progress;

  /// Waiting for the user's approval.
  final bool waiting;
}

/// The fixed scene of the validated prototypes: three agents, one waiting
/// for approval. It stands in for the demo agent source of the engine
/// (milestone J1).
abstract final class DemoScene {
  static const focus = DemoAgent(
    name: 'VPS · scraper',
    color: StatusColor.approval,
    activity: 'attend ton feu vert',
    time: 'maint.',
    waiting: true,
  );
  static const focusVerb = 'veut lancer';
  static const focusCommand = 'rm -rf ./cache && cargo build --release';
  static const focusWhen = 'maintenant';

  static const agents = [
    DemoAgent(name: 'Refacto API', color: StatusColor.working, activity: 'Edit src/routes.rs', time: '2:14', progress: .62),
    DemoAgent(name: 'Site vitrine', color: StatusColor.other, activity: 'npm test', time: '0:48', progress: .3),
    focus,
  ];

  static int get waitingCount => agents.where((a) => a.waiting).length;
}
