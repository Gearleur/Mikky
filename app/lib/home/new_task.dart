import 'package:flutter/widgets.dart';

import '../ui/brand_logo.dart';
import '../ui/feedback.dart';
import '../ui/field.dart';
import '../ui/thread_page.dart';
import '../ui/tokens.dart';

/// A new chat (2026-10-05: « comme pour l'agent, propre et smooth, un chat
/// vide »): the page of an agent ([ThreadPage]) with its thread empty —
/// « Qu'est-ce qu'on lance ? » in its middle — and the field with its
/// folder and model half inside. Opened from the home (« + », the tools,
/// the Chat mode) as an agent's page is; once sent, it becomes that
/// agent's page. Shared by the app and the boards.
class NewChatView extends StatelessWidget {
  const NewChatView({super.key, required this.composer, required this.back, this.status, this.error, this.mikky, this.drawMikky = true});

  /// The field (a [Composer] with its options).
  final Widget composer;
  final VoidCallback back;

  /// While it starts: « Démarrage… », with a spinner.
  final String? status;
  final String? error;

  /// In the notch, where Mikky stands.
  final MikkyBeside? mikky;

  /// False: the island draws its own Mikky (the app).
  final bool drawMikky;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return ThreadPage(
      back: back,
      mikky: mikky,
      drawMikky: drawMikky,
      composer: composer,
      empty: Column(mainAxisSize: MainAxisSize.min, children: [
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
    );
  }
}

/// The same with a still field, for the boards.
class NewChatSample extends StatelessWidget {
  const NewChatSample({super.key, this.status, this.error, this.mikky, this.folder = 'mikky', this.model = 'Claude'});

  final String? status, error;
  final MikkyBeside? mikky;
  final String folder, model;

  @override
  Widget build(BuildContext context) => NewChatView(
    back: () {},
    status: status,
    error: error,
    mikky: mikky,
    composer: Composer(
      placeholder: 'Que doit faire l’agent ?',
      glass: true,
      options: Row(mainAxisSize: MainAxisSize.min, children: [
        ComposerChip(folder, icon: 'folder', onTap: () {}),
        const SizedBox(width: 6),
        ComposerChip(model, leading: const BrandLogo(Brand.claude, size: 12), onTap: () {}),
      ]),
    ),
  );
}
