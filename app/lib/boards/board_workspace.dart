import 'package:flutter/widgets.dart';

import '../home/home_app.dart';
import '../ui/tokens.dart';
import 'canvas.dart';

final workspaceBoard = BoardSpec(
  'Espace',
  'La grande fenêtre · mêmes agents, même moteur',
  (context) => [
    BoardSection(
      title: 'Un écran sur tes agents',
      note: 'La fenêtre --home partage les sessions et les permissions avec l’île. Windows et WSL indiquent leur disponibilité réelle. Les équipes et les machines distantes viendront dans les étapes suivantes.',
      frames: [
        SizedBox(
          width: 1080,
          height: 720,
          child: WorkspaceShell(
            windows: 'Prêt',
            wsl: 'Prêt',
            count: 0,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  'Tes sessions apparaissent ici.\n\nDans l’application, tu peux lancer un agent, ouvrir son fil et répondre à ses demandes.',
                  style: uiText(18, color: MikkyUi.of(context).text2, height: 1.6),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  ],
);
