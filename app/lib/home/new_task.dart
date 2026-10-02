import 'package:flutter/widgets.dart';

import '../ui/brand_logo.dart';
import '../ui/feedback.dart';
import '../ui/field.dart';
import '../ui/tokens.dart';

/// The home's Chat (2026-10-02): the old « Nouvel agent », in the home —
/// « Qu'est-ce qu'on lance ? » in the middle, the field at the bottom with
/// its folder and model half inside. No Mikky in the middle: the home's
/// own is at the top left. Shared by the app and the boards.
class NewTaskView extends StatelessWidget {
  const NewTaskView({super.key, required this.composer, this.status, this.error});

  /// The field (a [Composer] with its options).
  final Widget composer;

  /// While it starts: « Démarrage… », with a spinner.
  final String? status;
  final String? error;

  /// The field's room at the bottom: 40 high, 8 more and 12 below for
  /// its options, 12 from the edge.
  static const _field = 72.0;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Stack(children: [
      Positioned.fill(
        bottom: _field,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Qu’est-ce qu’on lance ?', style: uiText(TextSize.body, weight: FontWeight.w500, color: ui.text2)),
          if (status != null) ...[
            const SizedBox(height: 10),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Spinner(size: 14),
              const SizedBox(width: 8),
              Text(status!, style: uiText(TextSize.small, color: ui.text2)),
            ]),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Text(error!, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: uiText(TextSize.small, color: ui.red)),
            ),
        ]),
      ),
      Positioned(left: 20, right: 20, bottom: 12, child: composer),
    ]);
  }
}

/// The same with a still field, for the boards.
class NewTaskSample extends StatelessWidget {
  const NewTaskSample({super.key, this.status, this.error, this.folder = 'mikky', this.model = 'Claude'});

  final String? status, error;
  final String folder, model;

  @override
  Widget build(BuildContext context) => NewTaskView(
    status: status,
    error: error,
    composer: Composer(
      placeholder: 'Que doit faire l’agent ?',
      options: Row(mainAxisSize: MainAxisSize.min, children: [
        ComposerChip(folder, icon: 'folder', onTap: () {}),
        const SizedBox(width: 6),
        ComposerChip(model, leading: const BrandLogo(Brand.claude, size: 12), onTap: () {}),
      ]),
    ),
  );
}
