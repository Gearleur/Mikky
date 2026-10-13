import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void main() {
  test('a child limit blocks the parent until the user resumes the task', () {
    final at = DateTime(2026, 10, 8, 13, 24);
    final parent = SessionLog()..applyAll([TurnStarted(at: at), UserMessage('Vérifie', at: at)]);
    final child = SessionLog()
      ..applyAll([
        TurnStarted(at: at),
        TurnEnded(
          StopReason.rateLimited,
          message: "You've hit your session limit · resets 2:50pm (Europe/Paris)",
          at: at.add(const Duration(seconds: 1)),
        ),
      ]);
    parent.subAgents = [SubAgentLog(id: 'a85', name: 'Front', log: child)];
    expect(parent.statusAt(at), AgentStatus.rateLimited);
    expect(parent.limitResetsAt, DateTime(2026, 10, 8, 14, 50));
    expect(parent.detail, 'Limite atteinte · reprend à 14 h 50');
    parent.apply(const TurnEnded(StopReason.endTurn));
    parent.apply(TurnStarted(at: at.add(const Duration(seconds: 2))));
    expect(parent.statusAt(at), AgentStatus.rateLimited); // reads an automated notification
    parent.apply(TurnStarted(at: at.add(const Duration(hours: 2))));
    parent.apply(UserMessage('Reprends', at: at.add(const Duration(hours: 2))));
    expect(parent.statusAt(at.add(const Duration(hours: 2))).isBusy, isTrue);
    expect(parent.limitResetsAt, isNull);
  });

  test('a nested parent resuming clears its old child limit', () {
    final at = DateTime(2026, 10, 8, 13);
    final root = SessionLog()..applyAll([TurnStarted(at: at), UserMessage('Vérifie', at: at)]);
    final middle = SessionLog()..applyAll([TurnStarted(at: at), UserMessage('Relis', at: at)]);
    final child = SessionLog()
      ..applyAll([TurnStarted(at: at), TurnEnded(StopReason.rateLimited, message: 'Rate limit reached', at: at)]);
    root.subAgents = [SubAgentLog(id: 'middle', name: 'Relecteur', log: middle)];
    middle.subAgents = [SubAgentLog(id: 'child', name: 'Lecteur', log: child)];
    expect(root.statusAt(at), AgentStatus.rateLimited);
    middle.apply(TurnStarted(at: at.add(const Duration(hours: 2))));
    middle.apply(UserMessage('Reprends', at: at.add(const Duration(hours: 2))));
    expect(root.limitSource, isNull);
  });
  test('an async agent survives its parent turn and is found by agent id or tool id', () {
    final log = SessionLog()
      ..applyAll([
        const TurnStarted(),
        const ToolCallEvent('toolu_1', name: 'Agent', title: 'Front', status: ToolStatus.running),
        const ToolCallEvent('toolu_1', agent: 'a85', status: ToolStatus.running),
        const TurnEnded(StopReason.endTurn),
      ]);
    final child = SessionLog()..apply(const TurnStarted());
    final link = SubAgentLog(id: 'a85', name: 'Front', tool: 'toolu_1', log: child);
    log.subAgents = [link];
    final tool = log.items.whereType<ToolItem>().single;
    expect(tool.active, isTrue);
    expect(tool.agent, 'a85');
    expect(log.subAgentOf(tool), same(link));
    expect(log.subAgentOf(const ToolItem('toolu_1')), same(link));
    expect(link.status, ToolStatus.running);
    child.apply(const TurnEnded(StopReason.endTurn));
    expect(link.status, ToolStatus.completed);
    child.apply(const TurnStarted());
    expect(
      SubAgentLog(id: 'a85', name: 'Front', log: child, reportedStatus: ToolStatus.completed).status,
      ToolStatus.completed,
    );
    log.apply(const ToolCallEvent('toolu_1', status: ToolStatus.completed));
    expect(log.items.whereType<ToolItem>().single.active, isFalse);
  });
}
