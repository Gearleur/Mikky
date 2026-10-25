/// Claude's public hook form format, used only for labelled synthetic requests.
Map<String, Object?> walkthroughQuestion(String text, String header, List<String> choices, {bool multiple = false}) => {
  'question': text,
  'header': header,
  'multiSelect': multiple,
  'options': [
    for (final label in choices) {'label': label, 'description': 'Réponse de démonstration : $label'},
  ],
};

List<List<Map<String, Object?>>> walkthroughForms() => [
  [
    walkthroughQuestion('TEST · Quel thème veux-tu pour cette démonstration ?', 'Thème', [
      'Clair',
      'Sombre',
      'Comme Windows',
    ]),
  ],
  [
    walkthroughQuestion('TEST · Quels éléments veux-tu observer ensemble ?', 'Plusieurs choix', [
      'Messages',
      'Questions',
      'Sons',
      'Transitions',
    ], multiple: true),
  ],
  [
    walkthroughQuestion(
      'TEST · Quelle amélioration voudrais-tu ? Choisis Autre pour écrire ta réponse.',
      'Réponse libre',
      ['Lisibilité', 'Disposition'],
    ),
  ],
  [
    walkthroughQuestion('TEST · Quelle base de données pour cet exemple ?', 'Base', ['SQLite', 'Postgres']),
    walkthroughQuestion('TEST · Quels tests ajouter ? Reviens en arrière pour vérifier ton brouillon.', 'Tests', [
      'Unitaires',
      'Intégration',
      'Visuels',
    ], multiple: true),
    walkthroughQuestion('TEST · Quand exécuter cette tâche fictive ?', 'Quand', ['Maintenant', 'Plus tard']),
  ],
  [
    walkthroughQuestion(
      'TEST · Cette question est volontairement longue. Vérifie que tu peux lire tout le texte, faire défiler les réponses, '
          'retrouver la conversation avec Contexte et revenir ici avec Question sans perdre tes sélections. '
          'Utilise aussi Plus tard puis rouvre la tuile TEST NOTCH. Quelles situations faut-il vérifier ?',
      'Question longue',
      [
        'Un long message qui revient sur plusieurs lignes',
        'Plusieurs réponses avec des descriptions détaillées',
        'Une réponse libre à saisir au clavier',
        'Une question remise à plus tard puis rouverte',
        'Un retour au contexte avant la validation',
        'Une autre tâche qui continue pendant la question',
      ],
      multiple: true,
    ),
  ],
];

Map<String, Object> walkthroughAnswers(int index, List<Map<String, Object?>> questions) => index == 2
    ? {'q1_custom': 'Mieux identifier l’agent et regrouper la question avec ses choix.'}
    : {
        for (final (i, q) in questions.indexed)
          'q${i + 1}': q['multiSelect'] == true
              ? [(q['options'] as List).first['label'] as String, (q['options'] as List)[1]['label'] as String]
              : (q['options'] as List).first['label'] as String,
      };
