import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../settings.dart';
import '../theme.dart';

/// Development tool (spec §5.6): Mikky in large, a button for each state,
/// emote and gesture, sliders for his proportions. Used to tune and
/// validate the expressions with the user before freezing them.
class TuningApp extends StatelessWidget {
  const TuningApp({super.key, required this.tuning});

  final MikkyTuning tuning;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Réglage de Mikky',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Geist',
          colorSchemeSeed: const Color(0xFF007AFF),
          scaffoldBackgroundColor: const Color(0xFFF5F5F7),
        ),
        home: _TuningPage(tuning: tuning),
      );
}

const _stateLabels = {
  MikkyState.idle: 'Au repos',
  MikkyState.working: 'Travaille',
  MikkyState.thinking: 'Réfléchit',
  MikkyState.searching: 'Cherche',
  MikkyState.approval: 'Attend ton feu vert',
  MikkyState.question: 'Question',
  MikkyState.error: 'Erreur',
  MikkyState.finished: 'Terminé',
  MikkyState.rateLimited: 'Limité',
  MikkyState.sleeping: 'Dort',
  MikkyState.dizzy: 'Sonné',
};

const _emoteLabels = {
  MikkyEmote.love: 'Amour',
  MikkyEmote.surprised: 'Surpris',
  MikkyEmote.proud: 'Fier',
  MikkyEmote.wink: "Clin d'œil",
  MikkyEmote.yawn: 'Bâille',
  MikkyEmote.content: 'Content',
  MikkyEmote.annoyed: 'Agacé',
};

class _TuningPage extends StatefulWidget {
  const _TuningPage({required this.tuning});

  final MikkyTuning tuning;

  @override
  State<_TuningPage> createState() => _TuningPageState();
}

class _TuningPageState extends State<_TuningPage> with SingleTickerProviderStateMixin {
  final _mikky = Mikky();
  late final Ticker _ticker = createTicker(_onTick)..start();
  late MikkyTuning _tuning = widget.tuning.copy();
  Duration _last = Duration.zero;
  Offset? _pointer;
  bool _dark = false;
  MikkyState _state = MikkyState.idle;

  static const _bigRadius = 110.0;
  final _bigKey = GlobalKey();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero ? 1 / 60 : math.min((elapsed - _last).inMicroseconds / 1e6, 1 / 20);
    _last = elapsed;
    final box = _bigKey.currentContext?.findRenderObject() as RenderBox?;
    var look = (0.0, 0.0);
    final p = _pointer;
    if (box != null && p != null) {
      final c = _bigCenter(box.size);
      look = Mikky.lookAt(p.dx - c.dx, p.dy - c.dy);
    }
    _mikky.update(dt, lookX: look.$1, lookY: look.$2);
    setState(() {});
  }

  Offset _bigCenter(Size size) => Offset(size.width / 2, size.height * .58);

  void _setState(MikkyState s) {
    _state = s;
    // Replay the entry gesture even when choosing the same state again.
    _mikky.setState(MikkyState.idle);
    _mikky.setState(s);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    await Settings.saveTuning(_tuning);
    messenger.showSnackBar(const SnackBar(content: Text('Enregistré. Relance l\'île (Quitter puis relancer) pour l\'appliquer.')));
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_tuning.toJson())));
    messenger.showSnackBar(const SnackBar(content: Text('Valeurs copiées.')));
  }

  @override
  Widget build(BuildContext context) {
    final island = _dark ? MikkyTheme.dark : MikkyTheme.light;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _bigCard(island)),
                  const SizedBox(height: 12),
                  SizedBox(height: 120, child: _previews()),
                ],
              ),
            ),
          ),
          SizedBox(width: 380, child: _controls(context)),
        ],
      ),
    );
  }

  Widget _bigCard(MikkyTheme island) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: MouseRegion(
          onHover: (e) {
            _pointer = e.localPosition;
            final box = _bigKey.currentContext?.findRenderObject() as RenderBox?;
            if (box == null) return;
            final over = (e.localPosition - _bigCenter(box.size)).distance < _bigRadius * 1.2;
            _mikky.hover(over);
            if (over) _mikky.pointerMoved();
          },
          onExit: (_) {
            _pointer = null;
            _mikky.hover(false);
          },
          child: GestureDetector(
            onTap: _mikky.boop,
            child: ColoredBox(
              key: _bigKey,
              color: _dark ? const Color(0xFF070708) : const Color(0xFFEEE9E1),
              child: LayoutBuilder(
                builder: (context, c) => CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: MikkyPainter(
                    geometry: MikkyGeometry.of(_mikky, _bigRadius, tuning: _tuning),
                    center: _bigCenter(Size(c.maxWidth, c.maxHeight)),
                    rim: island.mikkyRim,
                    statusColor: island.status,
                    foreground: island.foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// Mikky at his real sizes in the island (closed 9, open 28), on both
  /// island themes.
  Widget _previews() {
    Widget one(String label, double radius, MikkyTheme t) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.isLight ? Colors.white : const Color(0xFF070708),
                borderRadius: BorderRadius.circular(radius < 20 ? 18 : 24),
                border: Border.all(color: const Color(0x1F000000), width: .5),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: MikkyPainter(
                        geometry: MikkyGeometry.of(_mikky, radius, tuning: _tuning),
                        center: Offset(radius < 20 ? 30 : 60, radius < 20 ? 60 : 68),
                        rim: t.mikkyRim,
                        statusColor: t.status,
                        foreground: t.foreground,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 8,
                    child: Text(label, style: TextStyle(fontSize: 11, color: t.secondary)),
                  ),
                ],
              ),
            ),
          ),
        );
    return Row(
      children: [
        one('fermée · noir', 9, MikkyTheme.dark),
        one('fermée · blanc', 9, MikkyTheme.light),
        one('ouverte · noir', 28, MikkyTheme.dark),
        one('ouverte · blanc', 28, MikkyTheme.light),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    final t = _tuning;
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        );
    Widget slider(String label, double value, double min, double max, void Function(double) set) => Row(
          children: [
            SizedBox(width: 132, child: Text(label, style: const TextStyle(fontSize: 13))),
            Expanded(
              child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: (v) => setState(() => set(v))),
            ),
            SizedBox(width: 44, child: Text(value.toStringAsFixed(2), style: const TextStyle(fontFamily: 'Geist Mono', fontSize: 12))),
          ],
        );
    return Material(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        children: [
          section('États'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in MikkyState.values)
                ChoiceChip(label: Text(_stateLabels[s]!), selected: _state == s, onSelected: (_) => _setState(s)),
            ],
          ),
          section('Émotes'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in MikkyEmote.values) ActionChip(label: Text(_emoteLabels[e]!), onPressed: () => _mikky.play(e)),
            ],
          ),
          section('Gestes'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ActionChip(label: const Text('Cligner'), onPressed: _mikky.blink),
              ActionChip(label: const Text('Oreilles'), onPressed: () => _mikky.twitch()),
              ActionChip(label: const Text('Boop'), onPressed: _mikky.boop),
              ActionChip(label: const Text('Saut'), onPressed: _mikky.hop),
              ActionChip(label: const Text('Secousse'), onPressed: _mikky.shake),
              ActionChip(label: const Text('Roulade'), onPressed: _mikky.roll),
              ActionChip(label: const Text('Alerte'), onPressed: _mikky.alert),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Survole Mikky : il cligne. Reste immobile dessus 2 s : amour. Trois clics rapides : sonné.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          section('Proportions'),
          slider('Hauteur des yeux', t.eyeElevation, -.1, .4, (v) => t.eyeElevation = v),
          slider('Taille des yeux', t.eyeSize, .7, 1.4, (v) => t.eyeSize = v),
          slider('Allongement', t.eyeElongation, .8, 1.6, (v) => t.eyeElongation = v),
          slider('Écart des yeux', t.eyeSpread, .2, .45, (v) => t.eyeSpread = v),
          slider('Largeur du bas', t.bottomWiden, 0, .3, (v) => t.bottomWiden = v),
          slider('Hauteur oreilles', t.earHeight, .3, .8, (v) => t.earHeight = v),
          slider('Écart oreilles', t.earCenter, .45, .75, (v) => t.earCenter = v),
          slider('Largeur oreilles', t.earWidth, .7, 1.3, (v) => t.earWidth = v),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fond noir', style: TextStyle(fontSize: 13)),
            value: _dark,
            onChanged: (v) => setState(() => _dark = v),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: _save, child: const Text('Enregistrer')),
              OutlinedButton(onPressed: _copy, child: const Text('Copier les valeurs')),
              TextButton(
                onPressed: () => setState(() => _tuning = MikkyTuning()),
                child: const Text('Valeurs d\'origine'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
