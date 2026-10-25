import 'package:flutter/widgets.dart';

import '../agents/agents_service.dart';
import '../ui/content/side.dart';
import '../ui/controls/buttons.dart';
import '../ui/foundation/tokens.dart';

/// Read-only information from the current client, without a model call.
class SettingsDiagnostics extends StatelessWidget {
  const SettingsDiagnostics({super.key, required this.service, required this.back});

  final AgentsService service;
  final VoidCallback back;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final ui = MikkyUi.of(context);
      final lines = [
        ('Application', 'Mikky 0.1.0'),
        (
          'Moteur',
          switch (service.backend) {
            BackendState.online => 'Connecté',
            BackendState.connecting => 'Connexion en cours',
            BackendState.reconnecting => 'Reconnexion en cours',
            BackendState.unavailable => 'Indisponible',
          },
        ),
        ('Conversations connues', '${service.source.homeEntries.length}'),
        ('Lancement des agents', service.canLaunch ? 'Disponible' : 'Indisponible'),
      ];
      return Column(
        children: [
          SideHead(
            title: 'Diagnostics',
            small: true,
            leading: RoundButton('left', size: 34, tooltip: 'Retour', onPressed: back),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ReadingColumn(
                child: Column(
                  children: [
                    for (final (label, value) in lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(label, style: uiText(TextSize.small, color: ui.text2)),
                            ),
                            Text(value, style: uiText(TextSize.small, color: ui.text)),
                          ],
                        ),
                      ),
                    if (service.backendError case final error?)
                      Text(error, style: uiText(TextSize.caption, color: ui.text2)),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
