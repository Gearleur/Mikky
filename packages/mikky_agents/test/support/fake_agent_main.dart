import 'dart:io';

import 'fake_agent.dart';

/// The fake agent as a real process, on stdin / stdout (process tests).
void main() {
  FakeAgent(stdin, stdout);
}
