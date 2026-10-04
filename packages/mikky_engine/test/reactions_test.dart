import 'dart:math' as math;

import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

Agent agent(String id, AgentStatus s) => Agent(id: id, name: id, status: s, startedAt: 0, statusSince: 0);

void main() {
  group('reactionTo', () {
    test('each alert has its sound and its line', () {
      expect(reactionTo(AgentStatus.working, AgentStatus.approval).cue, MikkyCue.approval);
      expect(reactionTo(AgentStatus.working, AgentStatus.question).cue, MikkyCue.question);
      expect(reactionTo(AgentStatus.working, AgentStatus.error).cue, MikkyCue.error);
      expect(reactionTo(AgentStatus.working, AgentStatus.rateLimited).cue, MikkyCue.rateLimited);
      expect(reactionTo(AgentStatus.working, AgentStatus.finished).cue, MikkyCue.finished);
      expect(reactionTo(AgentStatus.working, AgentStatus.approval).line, isNotEmpty);
    });

    test('moving between tools is silent; starting to work is not', () {
      expect(reactionTo(AgentStatus.working, AgentStatus.thinking).isEmpty, isTrue);
      expect(reactionTo(AgentStatus.thinking, AgentStatus.searching).isEmpty, isTrue);
      expect(reactionTo(AgentStatus.idle, AgentStatus.thinking).cue, MikkyCue.launch);
      expect(reactionTo(null, AgentStatus.working).cue, MikkyCue.launch);
      expect(reactionTo(AgentStatus.approval, AgentStatus.working).cue, MikkyCue.launch);
    });

    test('no change, no reaction', () {
      for (final s in AgentStatus.values) {
        expect(reactionTo(s, s).isEmpty, isTrue);
      }
    });
  });

  test('thinking and searching show as working (2026-10-01)', () {
    expect(mikkyStateOf(AgentStatus.searching), MikkyState.working);
    expect(mikkyStateOf(AgentStatus.thinking), MikkyState.working);
    expect(mikkyStateOf(null), MikkyState.idle);
    expect(mikkyStateOf(AgentStatus.paused), MikkyState.idle);
  });

  group('MikkyDirector', () {
    test('agents already there are not news', () {
      final d = MikkyDirector();
      expect(d.agents([agent('a', AgentStatus.approval)], null, 0), isEmpty);
      final out = d.agents([agent('a', AgentStatus.finished)], null, 1);
      expect(out.single.agentId, 'a');
      expect(out.single.reaction.cue, MikkyCue.finished);
    });

    test('every agent reacts, not only the one in focus', () {
      final d = MikkyDirector()..agents([agent('a', AgentStatus.working), agent('b', AgentStatus.working)], null, 0);
      final out = d.agents([agent('a', AgentStatus.working), agent('b', AgentStatus.error)], agent('a', AgentStatus.working), 1);
      expect(out.map((r) => r.agentId), ['b']);
    });

    test('an alert shows at once, then work again', () {
      final d = MikkyDirector();
      final a = agent('a', AgentStatus.working);
      d.agents([a], a, 0);
      expect(d.state, MikkyState.working);
      final w = agent('a', AgentStatus.approval);
      d.agents([w], w, 1);
      expect(d.state, MikkyState.approval);
      final t = agent('a', AgentStatus.thinking);
      d.agents([t], t, 2);
      expect(d.state, MikkyState.working);
    });

    test('falls asleep after a while with nothing to do, wakes up on news', () {
      final d = MikkyDirector(sleepAfter: 600);
      d.agents([agent('a', AgentStatus.finished)], null, 0);
      expect(d.nextDeadline, 600);
      expect(d.advance(599).isEmpty, isTrue);
      final r = d.advance(600);
      expect(r.emote, MikkyEmote.yawn);
      expect(r.cue, MikkyCue.sleep);
      expect(d.state, MikkyState.sleeping);
      expect(d.nextDeadline, isNull);
      final out = d.agents([agent('a', AgentStatus.working)], agent('a', AgentStatus.working), 700);
      expect(out.first.reaction.cue, MikkyCue.wake);
      expect(d.sleeping, isFalse);
      expect(d.state, MikkyState.working);
    });

    test('never sleeps while an agent works or waits', () {
      final d = MikkyDirector(sleepAfter: 10);
      d.agents([agent('a', AgentStatus.approval)], agent('a', AgentStatus.approval), 0);
      expect(d.advance(1000).isEmpty, isTrue);
      expect(d.sleeping, isFalse);
    });

    test('the user wakes him up', () {
      final d = MikkyDirector(sleepAfter: 10)..agents(const [], null, 0);
      d.advance(10);
      expect(d.user(11).cue, MikkyCue.wake);
      expect(d.user(12).isEmpty, isTrue);
      expect(d.nextDeadline, 22);
    });
  });

  group('Mikky by himself', () {
    void run(Mikky m, double seconds) {
      for (var i = 0; i < (seconds * 60).round(); i++) {
        m.update(1 / 60);
      }
    }

    test('a slap annoys him, three make him dizzy, with their sounds', () {
      final cues = <MikkyCue>[];
      final m = Mikky(random: math.Random(1))..onSound = cues.add;
      m.slap();
      expect(m.emote, MikkyEmote.annoyed);
      run(m, .2);
      m.slap();
      run(m, .2);
      m.slap();
      expect(cues, [MikkyCue.slap, MikkyCue.slap, MikkyCue.dizzy]);
      expect(m.state, MikkyState.dizzy);
    });

    test('loved after 1.9 s under a still cursor, once', () {
      final cues = <MikkyCue>[];
      final m = Mikky(random: math.Random(1))..onSound = cues.add;
      m.hover(true);
      run(m, 2);
      expect(m.emote, MikkyEmote.love);
      run(m, 3);
      expect(cues, [MikkyCue.love]);
    });

    test('a reaction plays its emote', () {
      final m = Mikky(random: math.Random(1));
      m.react(reactionTo(AgentStatus.working, AgentStatus.finished));
      expect(m.emote, MikkyEmote.content);
    });
  });
}
