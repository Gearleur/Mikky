import '../agents/agent.dart';
import 'mikky.dart';

/// A sound, by what it means; the app picks the file (`app/lib/sound/`).
/// Silent updates (an agent moving from one tool to the next) have none.
enum MikkyCue {
  /// Mikky starts (the app opens).
  hello,

  /// The island opens or closes (by the user or for an alert).
  open,
  close,

  /// The cursor bumps the edge: Mikky peeks out and says hello.
  peek,

  /// Going to a page, coming back from one, a choice.
  navigate,
  back,
  select,

  /// An agent starts: launched by the user, or a new turn.
  launch,

  /// A message sent to an agent.
  send,

  /// An agent needs the user.
  approval,
  question,
  error,
  rateLimited,

  /// An agent is done.
  finished,

  /// The user's answer: yes, or no.
  approve,
  deny,

  /// Mikky himself: loved (hovered long), slapped, dizzy, falling asleep,
  /// waking up.
  love,
  slap,
  dizzy,
  sleep,
  wake,
}

/// A one-off movement of Mikky (see [Mikky]'s gestures).
enum MikkyGesture { blink, twitch, alert, hop, shake, roll, squash }

/// What Mikky does about one event: his state from now on, an expression,
/// a movement, a sound, and what he would say (the island shows it next to
/// him). Everything optional: an empty reaction does nothing.
class MikkyReaction {
  const MikkyReaction({this.emote, this.gesture, this.cue, this.line});

  final MikkyEmote? emote;
  final MikkyGesture? gesture;
  final MikkyCue? cue;

  /// One short sentence about the agent (« veut lancer une commande »),
  /// after its name.
  final String? line;

  static const none = MikkyReaction();

  bool get isEmpty => emote == null && gesture == null && cue == null && line == null;

  @override
  String toString() => 'MikkyReaction($emote, $gesture, $cue, $line)';
}

/// Mikky's state for an agent's: one table, here, for the island, the home
/// and the boards. Thinking and searching are work: his working animation
/// (user request, 2026-10-01).
MikkyState mikkyStateOf(AgentStatus? s) => switch (s) {
  null || AgentStatus.idle || AgentStatus.paused => MikkyState.idle,
  AgentStatus.working || AgentStatus.thinking || AgentStatus.searching => MikkyState.working,
  AgentStatus.approval => MikkyState.approval,
  AgentStatus.question => MikkyState.question,
  AgentStatus.error => MikkyState.error,
  AgentStatus.finished => MikkyState.finished,
  AgentStatus.rateLimited => MikkyState.rateLimited,
};

/// What Mikky does when an agent goes from [from] (null: just appeared) to
/// [to]. Moving between working, thinking and searching is silent: only
/// the start of the work makes a sound.
MikkyReaction reactionTo(AgentStatus? from, AgentStatus to) {
  if (from == to) return MikkyReaction.none;
  final wasBusy = from != null && from.isBusy;
  return switch (to) {
    AgentStatus.working || AgentStatus.thinking || AgentStatus.searching =>
      wasBusy
          ? MikkyReaction.none
          : const MikkyReaction(gesture: MikkyGesture.hop, cue: MikkyCue.launch, line: 'se met au travail'),
    AgentStatus.approval => const MikkyReaction(
      gesture: MikkyGesture.alert,
      cue: MikkyCue.approval,
      line: 'attend ton feu vert',
    ),
    AgentStatus.question => const MikkyReaction(
      gesture: MikkyGesture.twitch,
      cue: MikkyCue.question,
      line: 'te pose une question',
    ),
    AgentStatus.error => const MikkyReaction(gesture: MikkyGesture.shake, cue: MikkyCue.error, line: 'a un problème'),
    AgentStatus.rateLimited => const MikkyReaction(
      gesture: MikkyGesture.twitch,
      cue: MikkyCue.rateLimited,
      line: 'a atteint sa limite',
    ),
    AgentStatus.finished => const MikkyReaction(emote: MikkyEmote.content, cue: MikkyCue.finished, line: 'a terminé'),
    AgentStatus.paused => const MikkyReaction(gesture: MikkyGesture.blink, line: 'est en pause'),
    AgentStatus.idle => wasBusy ? const MikkyReaction(gesture: MikkyGesture.blink) : MikkyReaction.none,
  };
}

/// What Mikky does when the user answers an agent.
MikkyReaction reactionToAnswer(AgentAnswer answer) => switch (answer) {
  AgentAnswer.allow || AgentAnswer.allowAlways => const MikkyReaction(emote: MikkyEmote.content, cue: MikkyCue.approve),
  AgentAnswer.deny => const MikkyReaction(gesture: MikkyGesture.shake, cue: MikkyCue.deny),
  AgentAnswer.retry => const MikkyReaction(gesture: MikkyGesture.hop, cue: MikkyCue.launch),
  AgentAnswer.dismiss => const MikkyReaction(gesture: MikkyGesture.blink, cue: MikkyCue.select),
};

/// One reaction, for one agent.
typedef AgentReaction = ({String agentId, MikkyReaction reaction});

/// Watches every agent and says how Mikky reacts, once per change; puts
/// him to sleep when nothing has happened for a while, and wakes him up.
///
/// Time-driven like the [IslandMachine]: feed it the agents and the
/// user's activity with their clock time, call [advance] at
/// [nextDeadline]. No timer of its own.
class MikkyDirector {
  MikkyDirector({this.sleepAfter = 600});

  /// Seconds without any agent at work or waiting, and without the user
  /// touching the island, before Mikky falls asleep.
  final double sleepAfter;

  final Map<String, AgentStatus> _last = {};
  double _lastActivity = 0;
  bool _sleeping = false;
  bool _started = false;

  MikkyState _shown = MikkyState.idle;

  /// True while Mikky sleeps.
  bool get sleeping => _sleeping;

  /// The state to show for the agent in focus, or asleep.
  MikkyState get state => _sleeping ? MikkyState.sleeping : _shown;

  /// The agents now, and which one Mikky stands for. Returns the
  /// reactions to play, one per agent that changed; the first time, none
  /// (agents already there are not news).
  List<AgentReaction> agents(List<Agent> agents, Agent? focus, double now) {
    if (!_started) _lastActivity = now;
    final out = <AgentReaction>[];
    final seen = <String>{};
    for (final a in agents) {
      seen.add(a.id);
      final before = _last[a.id];
      _last[a.id] = a.status;
      if (!_started) continue;
      final r = reactionTo(before, a.status);
      if (!r.isEmpty) out.add((agentId: a.id, reaction: r));
    }
    _last.removeWhere((id, _) => !seen.contains(id));
    _started = true;
    final lively = agents.any((a) => a.status.isBusy || a.status.needsYou);
    if (lively || out.isNotEmpty) _touch(now, out);
    _shown = mikkyStateOf(focus?.status);
    return out;
  }

  /// The user did something with the island (hover, click, key). Returns
  /// Mikky waking up, if he slept.
  MikkyReaction user(double now) {
    final woke = _sleeping;
    _lastActivity = now;
    _sleeping = false;
    return woke ? const MikkyReaction(gesture: MikkyGesture.blink, cue: MikkyCue.wake) : MikkyReaction.none;
  }

  void _touch(double now, List<AgentReaction> out) {
    _lastActivity = now;
    if (_sleeping) {
      _sleeping = false;
      out.insert(0, (agentId: '', reaction: const MikkyReaction(gesture: MikkyGesture.blink, cue: MikkyCue.wake)));
    }
  }

  /// When Mikky falls asleep, unless something happens before.
  double? get nextDeadline => _sleeping || _lively ? null : _lastActivity + sleepAfter;

  bool get _lively => _last.values.any((s) => s.isBusy || s.needsYou);

  /// Applies what is due at [now]. Returns Mikky falling asleep (a yawn
  /// first), if he does.
  MikkyReaction advance(double now) {
    if (!_sleeping && !_lively && now - _lastActivity >= sleepAfter) {
      _sleeping = true;
      return const MikkyReaction(emote: MikkyEmote.yawn, cue: MikkyCue.sleep);
    }
    return MikkyReaction.none;
  }
}

/// Plays a reaction on Mikky (its sound is the app's business).
extension MikkyReacts on Mikky {
  void react(MikkyReaction r) {
    switch (r.gesture) {
      case MikkyGesture.blink:
        blink();
      case MikkyGesture.twitch:
        twitch();
      case MikkyGesture.alert:
        alert();
      case MikkyGesture.hop:
        hop(small: true);
      case MikkyGesture.shake:
        shake();
      case MikkyGesture.roll:
        roll();
      case MikkyGesture.squash:
        squash();
      case null:
        break;
    }
    final e = r.emote;
    if (e != null) play(e);
  }
}
