import 'package:flutter/widgets.dart';

import 'buttons.dart';
import 'tokens.dart';

/// A connection notice, shared by the live app and its design boards.
class BackendStatus extends StatelessWidget {
  const BackendStatus({super.key, required this.title, required this.message, this.retry, this.warning = false});
  final String title, message;
  final VoidCallback? retry;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      color: ui.well,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: uiText(13, weight: FontWeight.w600, color: warning ? ui.amber : ui.blue),
          ),
          const SizedBox(height: 5),
          Text(message, style: uiText(12, color: ui.text2, height: 1.4)),
          if (retry != null) ...[const SizedBox(height: 8), MButton('Réessayer', small: true, onPressed: retry)],
        ],
      ),
    );
  }
}
