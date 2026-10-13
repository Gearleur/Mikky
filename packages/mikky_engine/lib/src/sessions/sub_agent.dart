import 'session_event.dart';
import 'session_log.dart';

/// A child's thread, kept under the tool that launched it.
class SubAgentLog {
  const SubAgentLog({required this.id, required this.name, required this.log, this.tool, this.reportedStatus});

  final String id;
  final String name;
  final String? tool;
  final SessionLog log;
  final ToolStatus? reportedStatus;

  ToolStatus get status => reportedStatus == ToolStatus.completed || reportedStatus == ToolStatus.failed
      ? reportedStatus!
      : log.working
      ? ToolStatus.running
      : switch (log.turns.lastOrNull?.reason) {
          StopReason.error || StopReason.rateLimited || StopReason.cancelled => ToolStatus.failed,
          null => ToolStatus.pending,
          _ => ToolStatus.completed,
        };
}
