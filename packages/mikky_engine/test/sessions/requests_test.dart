import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

Agent _a(String id, AgentStatus s, double since) => Agent(id: id, name: id, status: s, startedAt: 0, statusSince: since);

void main() {
  test('questions and permissions first, then errors, then limits; the oldest first', () {
    final queue = requestQueue([
      _a('limit', AgentStatus.rateLimited, 1),
      _a('error', AgentStatus.error, 2),
      _a('late question', AgentStatus.question, 9),
      _a('working', AgentStatus.working, 0),
      _a('permission', AgentStatus.approval, 5),
      _a('done', AgentStatus.finished, 0),
    ]);
    expect(queue.map((a) => a.id), ['permission', 'late question', 'error', 'limit']);
  });

  test('a tie keeps the agents order', () {
    final queue = requestQueue([_a('b', AgentStatus.approval, 3), _a('a', AgentStatus.question, 3)]);
    expect(queue.map((a) => a.id), ['b', 'a']);
  });

  test('without limits, or some agents left out', () {
    final agents = [_a('l', AgentStatus.rateLimited, 0), _a('q', AgentStatus.question, 1), _a('e', AgentStatus.error, 2)];
    expect(requestQueue(agents, limits: false).map((a) => a.id), ['q', 'e']);
    expect(requestQueue(agents, skip: {'q'}).map((a) => a.id), ['e', 'l']);
  });

  test('a limit alone does not open the island on it', () {
    expect(opensOnRequest(requestQueue([_a('l', AgentStatus.rateLimited, 0)])), isFalse);
    expect(opensOnRequest(requestQueue([_a('e', AgentStatus.error, 0)])), isTrue);
  });
}
