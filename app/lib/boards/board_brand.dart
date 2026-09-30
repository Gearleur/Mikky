import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/brand_logo.dart';
import '../ui/feedback.dart';
import '../ui/icons.dart';
import '../ui/pixel_fx.dart';
import '../ui/side.dart';
import '../ui/tokens.dart';
import 'canvas.dart';

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}${c.a < 1 ? ' · ${(c.a * 100).round()} %' : ''}';

/// A color: its square, its name, its value.
class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.color, {this.use});

  final String name;
  final Color color;
  final String? use;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return SizedBox(
      width: 150,
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9), border: Border.all(color: ui.line)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: uiText(12.5, weight: FontWeight.w600, color: ui.text)),
            Text(_hex(color), style: uiText(10.5, mono: true, color: ui.text3)),
            if (use != null) Text(use!, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(10.5, color: ui.text3)),
          ]),
        ),
      ]),
    );
  }
}

Widget _grid(List<Widget> children, {double width = 640}) =>
    SizedBox(width: width, child: Wrap(spacing: 14, runSpacing: 14, children: children));

/// What the brand still misses, to decide together.
class _Missing extends StatelessWidget {
  const _Missing();

  static const _items = [
    ('Nom et logo', 'Un logo « Mikky » : le chat en pixels ? Un mot-symbole (Geist, gras, espacé) ? Une icône d’app à la même grille de pixels que les feux d’artifice.'),
    ('Couleur signature', 'Aujourd’hui : noir, blanc, gris et les couleurs d’état (celles d’Apple). Il manque une couleur à nous, pour les liens, le focus, la sélection : un violet « magie » ?'),
    ('Palette pixel officielle', 'Les palettes violet, bleu, orange, rouge, jaune, gris, vert : à figer (4 niveaux chacune) et à nommer.'),
    ('Typographie', 'Geist et Geist Mono partout. Il manque une échelle nommée (titre, corps, légende, code) et peut-être une police pixel pour les titres ou les chiffres.'),
    ('Mikky en pixels', 'Mikky est dessiné en courbes ; la marque est en pixels. Une version pixel de Mikky (icône, zone de notification, favicon) ?'),
    ('Menus à nos couleurs', 'Le choix de l’agent, du modèle et du dossier passe par le menu natif de Windows : pas de survol à nous, pas nos couleurs. À refaire en composant.'),
    ('Infobulles', 'Les infobulles sont celles de Windows. Une bulle blanche à ombre douce, comme la capture « Bold : Ctrl + B ».'),
    ('Sons', 'Aucun son. Un petit « bip » pixel quand un agent attend ou finit ?'),
    ('Mouvement', 'Une règle écrite : ressorts (gelée 95 / 0,38, sélecteurs 380 / 0,70), vitesses par état, 30 i/s pour les boucles.'),
    ('Écran de connexion, réglages', 'Pas encore sur les planches : la connexion à Claude / Codex (lien, code) et un écran de réglages.'),
    ('Maquettes HTML', 'design/prototypes/ n’a pas suivi : lignes sans cartes, pixels, Oui / Non à plat, chat sans bulles. Les planches deviennent la référence ?'),
  ];

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return SizedBox(
      width: 700,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, (t, d)) in _items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 26, child: Text('${i + 1}.', style: uiText(13, weight: FontWeight.w600, color: ui.text3, tabular: true))),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$t  ', style: uiText(13, weight: FontWeight.w600, color: ui.text)),
                  TextSpan(text: d, style: uiText(13, color: ui.text2, height: 1.45)),
                ])),
              ),
            ]),
          ),
      ]),
    );
  }
}

final brandBoard = BoardSpec('Marque', 'Couleurs, pixels, lettres, Mikky, ce qui manque', (context) {
  final ui = MikkyUi.of(context);
  return [
    BoardSection(
      title: 'Couleurs de l’interface',
      note: 'Noir, blanc, gris (d’après boutons-lanceur.png). Mêmes noms en clair et en sombre : passe d’un thème à l’autre en bas à gauche.',
      frames: [
        BoardFrame(
          label: 'Fonds',
          width: 640,
          child: _grid([
            _Swatch('board', ui.board, use: 'fond du bureau'),
            _Swatch('island', ui.island, use: 'la fenêtre'),
            _Swatch('well', ui.well, use: 'creux, bulles'),
            _Swatch('track', ui.track, use: 'pistes, code'),
            _Swatch('thumb', ui.thumb, use: 'curseur, Oui'),
            _Swatch('hover', ui.hover, use: 'survol'),
            _Swatch('line', ui.line, use: 'traits'),
            _Swatch('ctlA → ctlB', ui.ctlA, use: 'boutons en relief'),
          ]),
        ),
        BoardFrame(
          label: 'Encre et texte',
          width: 480,
          child: _grid([
            _Swatch('ink', ui.ink, use: 'bouton principal'),
            _Swatch('text', ui.text, use: 'titres, texte'),
            _Swatch('text2', ui.text2, use: 'second plan'),
            _Swatch('text3', ui.text3, use: 'légendes'),
          ], width: 480),
        ),
        BoardFrame(
          label: 'États',
          width: 640,
          child: _grid([
            _Swatch('blue', ui.blue, use: 'travaille'),
            _Swatch('purple', ui.purple, use: 'réfléchit, internet'),
            _Swatch('amber', ui.amber, use: 'attend, commande'),
            _Swatch('green', ui.green, use: 'terminé, crée'),
            _Swatch('red', ui.red, use: 'erreur, supprime'),
            _Swatch('yellow', ui.yellow, use: 'limité, déplace'),
            _Swatch('grey', ui.grey, use: 'dort, historique'),
          ]),
        ),
      ],
    ),
    BoardSection(
      title: 'Pixels',
      note: 'La direction : Mikky, le chat magique, avec de l’informatique et des pixels. Chaque état est un petit feu d’artifice de pixels, à son rythme (attend 1,2 s, travaille 1,6 s, les autres 2,4 s, dort 4,8 s ; terminé figé).',
      frames: [
        BoardFrame(
          label: 'Palettes',
          note: 'Quatre niveaux, du cœur au bord. En clair, le cœur blanc prend une teinte de la couleur.',
          width: 520,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final st in UiStatus.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 30, child: StatusFx(st, size: 22)),
                  const SizedBox(width: 10),
                  for (final c in PixelFxPalette.of(st, ui).levels)
                    Container(width: 26, height: 26, margin: const EdgeInsets.only(right: 3), color: c),
                  const SizedBox(width: 10),
                  Text(PixelFxPalette.of(st, ui).name, style: uiText(12.5, color: ui.text2)),
                ]),
              ),
          ]),
        ),
        BoardFrame(
          label: 'États en grand',
          width: 520,
          child: Wrap(spacing: 18, runSpacing: 18, children: [for (final st in UiStatus.values) StatusFx(st, size: 56)]),
        ),
        BoardFrame(
          label: 'Effets à l’essai',
          note: 'Étincelle, feu d’artifice complet, galaxie ; et l’étoile qui réfléchit, mise de côté.',
          width: 520,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final k in [PixelFxKind.sparkle, PixelFxKind.firework, PixelFxKind.galaxy])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [for (final st in UiStatus.values) Padding(padding: const EdgeInsets.only(right: 10), child: StatusFx(st, kind: k, size: 40))]),
              ),
            const ThinkingStar(size: 40),
          ]),
        ),
      ],
    ),
    BoardSection(
      title: 'Lettres',
      frames: [
        BoardFrame(
          label: 'Geist et Geist Mono',
          width: 560,
          child: SizedBox(
            width: 560,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (size, weight, name, mono) in [
                (22.0, FontWeight.w600, 'Titre de planche · 22', false),
                (17.0, FontWeight.w600, 'Titre de page · 17', false),
                (15.0, FontWeight.w600, 'Bouton · 15', false),
                (14.0, FontWeight.w400, 'Texte, réponses · 14', false),
                (13.0, FontWeight.w400, 'Étapes, lignes · 13', false),
                (12.5, FontWeight.w600, 'Titres de groupes · 12,5', false),
                (11.5, FontWeight.w400, 'Légendes, heures · 11,5', false),
                (11.0, FontWeight.w400, 'dart test · Mono 11', true),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(name, style: uiText(size, weight: weight, mono: mono, color: ui.text)),
                ),
            ]),
          ),
        ),
      ],
    ),
    BoardSection(
      title: 'Mikky',
      note: 'Le vrai dessin de Mikky, en petit, dans quelques états (l’île et l’écran de réglage les montrent tous).',
      frames: [
        BoardFrame(
          label: 'En petit',
          width: 560,
          child: Wrap(spacing: 22, runSpacing: 12, children: [
            for (final (st, name) in [
              (MikkyState.idle, 'repos'),
              (MikkyState.working, 'travaille'),
              (MikkyState.thinking, 'réfléchit'),
              (MikkyState.approval, 'attend'),
              (MikkyState.finished, 'terminé'),
              (MikkyState.sleeping, 'dort'),
            ])
              Column(mainAxisSize: MainAxisSize.min, children: [
                MiniMikky(size: 64, state: st),
                Text(name, style: uiText(11.5, color: ui.text3)),
              ]),
          ]),
        ),
      ],
    ),
    BoardSection(
      title: 'Logos et icônes',
      frames: [
        BoardFrame(
          label: 'Outils',
          width: 520,
          child: Wrap(spacing: 18, runSpacing: 12, children: [
            for (final b in Brand.values)
              Row(mainAxisSize: MainAxisSize.min, children: [
                BrandLogo(b, size: 24),
                const SizedBox(width: 8),
                Text(b.label, style: uiText(13, weight: FontWeight.w600, color: ui.text)),
              ]),
          ]),
        ),
        BoardFrame(
          label: 'Icônes',
          width: 520,
          child: SizedBox(
            width: 520,
            child: Wrap(spacing: 14, runSpacing: 14, children: [
              for (final n in iconNames)
                Column(mainAxisSize: MainAxisSize.min, children: [
                  MikkyIcon(n, size: 22, color: ui.text),
                  const SizedBox(height: 3),
                  Text(n, style: uiText(9.5, color: ui.text3)),
                ]),
            ]),
          ),
        ),
      ],
    ),
    const BoardSection(
      title: 'Ce qui manque pour la marque',
      note: 'À décider ensemble ; rien de tout ça n’est fait.',
      frames: [BoardFrame(label: 'Liste', width: 700, child: _Missing())],
    ),
  ];
});
