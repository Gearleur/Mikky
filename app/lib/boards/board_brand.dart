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
    ('Nom et logo', 'Mikky : validé. Le logo, c’est Mikky lui-même : quatre propositions en haut de cette planche, à choisir ; puis l’icône de l’app et de la zone de notification.'),
    ('Couleurs signature', 'L’orange de ta capture et le même en bleu : gardées pour plus tard, en essai sur les feux d’artifice (section Pixels).'),
    ('Palette pixel officielle', 'Violet, bleu, orange, rouge, jaune, gris, vert : à figer (4 niveaux chacune) et à nommer. À voir.'),
    ('Typographie', 'En essai : choisis une police à gauche, toutes les planches passent dedans. Puis une échelle nommée (titre, corps, légende, code), et une police pixel pour les titres ou les chiffres ?'),
    ('Mikky en pixels', 'Une première tête en pixels est dans les propositions de logo (D). À voir.'),
    ('Menus à nos couleurs', 'Le choix de l’agent, du modèle et du dossier passe par le menu natif de Windows : pas de survol à nous, pas nos couleurs. À refaire en composant.'),
    ('Infobulles', 'Les infobulles sont celles de Windows. Une bulle blanche à ombre douce, comme la capture « Bold : Ctrl + B ».'),
    ('Sons', 'Aucun son. Un petit « bip » pixel quand un agent attend ou finit ?'),
    ('Mouvement', 'Une règle écrite : ressorts (gelée 95 / 0,38, sélecteurs 380 / 0,70), vitesses par état, 30 i/s pour les boucles.'),
    ('Écran de connexion, réglages', 'Pas encore sur les planches : la connexion à Claude / Codex (lien, code) et un écran de réglages.'),
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


/// A square tile of a given color, the mark in the middle: how the icon
/// looks on a dark or a light desktop.
class _Tile extends StatelessWidget {
  const _Tile({required this.child, required this.color, this.size = 120, this.radius = 28, this.line = false});

  final Widget child;
  final Color color;
  final double size;
  final double radius;
  final bool line;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: line ? Border.all(color: MikkyUi.of(context).line) : null,
    ),
    child: child,
  );
}

/// The ways to show Mikky as the logo (user request, 2026-09-30: the
/// mascot himself, more present).
enum _LogoKind {
  /// The whole cat, in the middle.
  whole,

  /// His head, big, filling the square.
  head,

  /// Peeking over the bottom edge.
  peek,

  /// In pixels.
  pixel,
}

/// Mikky as the logo on a square: the real drawing (he blinks and looks
/// around), or the pixel one.
class _Logo extends StatelessWidget {
  const _Logo(this.kind, {required this.size, required this.dark, this.tile = true});

  final _LogoKind kind;
  final double size;
  final bool dark;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final t = size;
    Widget mikky(double m, double centerY) => Positioned(
      left: (t - m) / 2,
      top: centerY - m * .54,
      child: MiniMikky(size: m, animate: t >= 32),
    );
    final child = switch (kind) {
      _LogoKind.whole => Center(child: MiniMikky(size: t * .95, animate: t >= 32)),
      _LogoKind.head => Stack(clipBehavior: Clip.hardEdge, children: [mikky(t * 1.3, t * .6)]),
      _LogoKind.peek => Stack(clipBehavior: Clip.hardEdge, children: [mikky(t * 1.3, t * .9)]),
      _LogoKind.pixel => Center(
        child: PixelMap(PixelMikky.head, colors: PixelMikky.colors, size: t * .78),
      ),
    };
    return MikkyUiTheme(
      ui: dark ? MikkyUi.dark : MikkyUi.light,
      child: tile
          ? Builder(
              builder: (context) => _Tile(
                // Dark: charcoal, so the black cat stands out.
                color: dark ? const Color(0xFF2A2A2E) : const Color(0xFFFFFFFF),
                size: t,
                radius: t * .23,
                line: !dark,
                child: ClipRRect(borderRadius: BorderRadius.circular(t * .23), child: SizedBox.square(dimension: t, child: child)),
              ),
            )
          : SizedBox.square(dimension: t, child: child),
    );
  }
}

/// One proposal for the logo: big on white and on black, then at the
/// sizes Windows shows (taskbar, notification area).
class _LogoProposal extends StatelessWidget {
  const _LogoProposal(this.kind);

  final _LogoKind kind;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        _Logo(kind, size: 120, dark: false),
        const SizedBox(width: 12),
        _Logo(kind, size: 120, dark: true),
      ]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        for (final (px, dark) in [(48.0, false), (32.0, false), (24.0, true), (16.0, true)]) ...[
          Column(mainAxisSize: MainAxisSize.min, children: [
            _Logo(kind, size: px, dark: dark),
            const SizedBox(height: 4),
            Text('${px.round()}', style: uiText(10, color: ui.text3, tabular: true)),
          ]),
          const SizedBox(width: 10),
        ],
        // Alone, no square: the notification area.
        Column(mainAxisSize: MainAxisSize.min, children: [
          _Logo(kind, size: 20, dark: !ui.isLight, tile: false),
          const SizedBox(height: 4),
          Text('seul', style: uiText(10, color: ui.text3)),
        ]),
      ]),
    ]);
  }
}

/// The fonts on trial (all free, SIL Open Font License): close to the one
/// of their picture (ALTMistral, Mistral's own, not free), and pixel ones.
const trialSans = ['Geist', 'Inter', 'Host Grotesk', 'Hanken Grotesk', 'Schibsted Grotesk', 'Onest', 'Space Grotesk'];
const trialPixel = ['Pixelify Sans', 'Silkscreen', 'Jersey 10', 'Tiny5', 'VT323'];
const trialMono = ['Geist Mono', 'JetBrains Mono', 'Space Mono'];

/// One font: the mark with the name, a sentence, the sizes the window
/// uses.
class _FontSample extends StatelessWidget {
  const _FontSample(this.family, {this.pixel = false});

  final String family;
  final bool pixel;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    TextStyle t(double size, {FontWeight weight = FontWeight.w400, Color? color, double height = 1.3, double tracking = 0}) =>
        uiText(size, weight: weight, color: color ?? ui.text, height: height, tracking: tracking).copyWith(fontFamily: family);
    return SizedBox(
      width: 380,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const MiniMikky(size: 46),
          const SizedBox(width: 6),
          Text('Mikky', style: t(36, weight: FontWeight.w600, height: 1.1, tracking: pixel ? 0 : -.02)),
        ]),
        const SizedBox(height: 10),
        Text('Tes agents.\nSous l’œil de Mikky.', style: t(26, weight: FontWeight.w500, height: 1.12, tracking: pixel ? 0 : -.015)),
        const SizedBox(height: 12),
        if (!pixel) ...[
          Text('Corrige les tests du moteur', style: t(14, weight: FontWeight.w600)),
          Text('Modifie island_machine.dart · il y a 2 min', style: t(12.5, color: ui.text2)),
          const SizedBox(height: 4),
          Text('Codex · 5 h : 38 % · repart à 17 h 10', style: t(11.5, color: ui.text3)),
        ] else
          Text('38 %  ·  17:10  ·  3 étapes  ·  12 agents', style: t(18, color: ui.text2)),
      ]),
    );
  }
}

final brandBoard = BoardSpec('Marque', 'Couleurs, pixels, lettres, Mikky, ce qui manque', (context) {
  final ui = MikkyUi.of(context);
  return [
    const BoardSection(
      title: 'Logo',
      note: 'Le logo, c’est Mikky lui-même : la mascotte, bien présente. Sur blanc et sur gris anthracite, puis aux tailles de Windows (barre des tâches, zone de notification).',
      frames: [
        BoardFrame(label: 'A · Mikky entier', note: 'Le vrai dessin, au milieu : il cligne et regarde autour.', width: 252, child: _LogoProposal(_LogoKind.whole)),
        BoardFrame(label: 'B · La tête en grand', note: 'Ses oreilles et ses yeux remplissent le carré.', width: 252, child: _LogoProposal(_LogoKind.head)),
        BoardFrame(label: 'C · Qui dépasse', note: 'Il passe la tête par le bas du carré.', width: 252, child: _LogoProposal(_LogoKind.peek)),
        BoardFrame(label: 'D · En pixels', note: 'Sa tête en 16 × 16, comme les feux d’artifice.', width: 252, child: _LogoProposal(_LogoKind.pixel)),
      ],
    ),
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
        BoardFrame(
          label: 'Couleurs signature',
          note: 'L’orange de ta capture, et le même en bleu (mêmes teintes, mêmes écarts). Gardées pour plus tard.',
          width: 330,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final pal in [PixelFxPalette.signatureOrange, PixelFxPalette.signatureBlue])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final c in pal.levels)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(width: 78, height: 56, color: c),
                        const SizedBox(height: 4),
                        Text(_hex(c), style: uiText(10.5, mono: true, color: ui.text3)),
                      ]),
                    ),
                ]),
              ),
          ]),
        ),
        BoardFrame(
          label: 'Feux d’artifice signature',
          note: 'Chaque effet en orange, en bleu ; et le calme aux deux couleurs, bleu au cœur, orange au bout.',
          width: 360,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final pal in [PixelFxPalette.signatureOrange, PixelFxPalette.signatureBlue])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final k in [PixelFxKind.fireworkSoft, PixelFxKind.firework, PixelFxKind.sparkle, PixelFxKind.galaxy])
                    Padding(padding: const EdgeInsets.only(right: 12), child: PixelFx(kind: k, palette: pal, size: 56, slow: k == PixelFxKind.fireworkSoft ? 2 / 3 : 1)),
                ]),
              ),
            const SignatureFirework(size: 56),
          ]),
        ),
      ],
    ),
    BoardSection(
      title: 'Lettres',
      note: 'Ta capture est en ALTMistral, la police maison de Mistral (pas libre). Voici des polices libres proches. Choisis-en une à gauche : toutes les planches passent dedans.',
      frames: [for (final f in trialSans) BoardFrame(label: f, width: 380, child: _FontSample(f))],
    ),
    BoardSection(
      title: 'Lettres pixel',
      note: 'Pour les titres ou les chiffres, avec la police du texte.',
      frames: [for (final f in trialPixel) BoardFrame(label: f, width: 380, child: _FontSample(f, pixel: true))],
    ),
    BoardSection(
      title: 'Échelle',
      note: 'Les tailles de la fenêtre, dans la police choisie à gauche.',
      frames: [
        BoardFrame(
          label: '${UiFonts.sans} et ${UiFonts.mono}',
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
