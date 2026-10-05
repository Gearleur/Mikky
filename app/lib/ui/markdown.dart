import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'motion.dart';
import 'tokens.dart';

/// Opens [url] in the default browser.
void openUrl(String url) {
  if (!url.startsWith('http://') && !url.startsWith('https://')) return;
  Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
}

/// The Markdown agents write in their answers, laid out to be read like a
/// note in Obsidian (user, 2026-10-05: « ultra quali »): paragraphs with
/// **bold**, *italics*, `code` and links ([text](url), bare https://…);
/// titles (#, ##, ###); « - » and « 1. » lists, nested; quotes (>);
/// tables (| a | b |); rules (---); ``` blocks of code, each with its
/// « Copier » button. Room between blocks, a little more before a title,
/// list items close together. The size and the line height come from the
/// text style around it.
class AgentText extends StatefulWidget {
  const AgentText(this.text, {super.key});

  final String text;

  @override
  State<AgentText> createState() => _AgentTextState();
}

/// What a block is, for the room around it.
enum _Kind { paragraph, item, heading, code, quote, table, rule }

class _AgentTextState extends State<AgentText> {
  final List<TapGestureRecognizer> _links = [];

  @override
  void dispose() {
    _disposeLinks();
    super.dispose();
  }

  void _disposeLinks() {
    for (final r in _links) {
      r.dispose();
    }
    _links.clear();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final base = DefaultTextStyle.of(context).style;
    _disposeLinks();
    final blocks = <_Block>[];
    final fence = RegExp(r'^```(\w*)\s*$', multiLine: true);
    var rest = widget.text;
    while (true) {
      final open = fence.firstMatch(rest);
      if (open == null) break;
      final close = fence.firstMatch(rest.substring(open.end));
      if (close == null) break;
      final before = rest.substring(0, open.start).trim();
      if (before.isNotEmpty) blocks.addAll(_blocks(before, ui, base));
      final code = rest.substring(open.end, open.end + close.start).replaceAll(RegExp(r'^\n|\n$'), '');
      blocks.add(_Block(CodeBlockView(code: code, language: open[1] ?? ''), _Kind.code));
      rest = rest.substring(open.end + close.end);
    }
    final after = rest.trim();
    if (after.isNotEmpty) blocks.addAll(_blocks(after, ui, base));
    if (blocks.length == 1) return blocks.single.child;
    final size = base.fontSize ?? TextSize.body;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < blocks.length; i++)
        Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : _gap(blocks[i - 1], blocks[i], size)), child: blocks[i].child),
    ]);
  }

  /// The room above [b]: items of one list close; a title well apart from
  /// what is above it, close to what it heads; else most of a line.
  static double _gap(_Block a, _Block b, double size) {
    if (b.kind == _Kind.heading) return (size * (b.level <= 2 ? 1.5 : 1.15)).roundToDouble();
    if (a.kind == _Kind.heading) return (size * .4).roundToDouble();
    if (a.kind == _Kind.item && b.kind == _Kind.item && !b.newList) return (size * .3).roundToDouble();
    return (size * .8).roundToDouble();
  }

  static final _listItem = RegExp(r'^(\s*)([-*•+]|\d+[.)])\s+(.*)$');
  static final _heading = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
  static final _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
  static final _tableSeparator = RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$');

  /// The blocks of [text] (no code in it). A list item is a marker and its
  /// text, the text in a column of its own so a long item wraps under
  /// itself; a line that goes on an item (indented, no marker) joins it
  /// (user request, 2026-09-30).
  List<_Block> _blocks(String text, MikkyUi ui, TextStyle base) {
    final out = <_Block>[];
    final size = base.fontSize ?? TextSize.body;
    final para = <String>[];
    final quote = <String>[];
    final table = <List<String>>[];
    (int, String, StringBuffer)? item;
    var lastWasItem = false;
    var blankSince = false;

    void flushPara() {
      if (para.isEmpty) return;
      out.add(_Block(Text.rich(_inline(para.join('\n'), ui)), _Kind.paragraph));
      para.clear();
      lastWasItem = false;
    }

    void flushQuote() {
      if (quote.isEmpty) return;
      out.add(_Block(
        Container(
          padding: const EdgeInsets.only(left: 12, top: 1, bottom: 1),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: ui.track, width: 3))),
          child: Text.rich(_inline(quote.join('\n'), ui), style: TextStyle(color: ui.text2)),
        ),
        _Kind.quote,
      ));
      quote.clear();
      lastWasItem = false;
    }

    void flushTable() {
      if (table.isEmpty) return;
      final columns = table.map((r) => r.length).reduce((a, b) => a > b ? a : b);
      final cellStyle = base.copyWith(fontSize: size - 1, height: 1.4);
      out.add(_Block(
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: ui.line)),
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            border: TableBorder(horizontalInside: BorderSide(color: ui.line)),
            children: [
              for (var r = 0; r < table.length; r++)
                TableRow(
                  decoration: r == 0 ? BoxDecoration(color: ui.well) : null,
                  children: [
                    for (var c = 0; c < columns; c++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Text.rich(
                          _inline(c < table[r].length ? table[r][c] : '', ui),
                          style: r == 0 ? cellStyle.copyWith(fontWeight: FontWeight.w600) : cellStyle,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        _Kind.table,
      ));
      table.clear();
      lastWasItem = false;
    }

    void flushItem() {
      final it = item;
      if (it == null) return;
      final (level, marker, buf) = it;
      final bullet = !RegExp(r'^\d').hasMatch(marker);
      out.add(_Block(
        Padding(
          padding: EdgeInsets.only(left: 2 + level * 18.0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: bullet ? 16 : 22,
              child: bullet
                  // A small round dot on the first line's middle.
                  ? Padding(
                      padding: EdgeInsets.only(top: (size * (base.height ?? 1.4) - 5) / 2, left: 2),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Container(width: 5, height: 5, decoration: BoxDecoration(color: level == 0 ? ui.text2 : ui.text3, shape: BoxShape.circle)),
                      ),
                    )
                  : Text(marker, style: TextStyle(color: ui.text2, fontWeight: FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            Expanded(child: Text.rich(_inline(buf.toString(), ui))),
          ]),
        ),
        _Kind.item,
        newList: !lastWasItem || blankSince,
      ));
      item = null;
      lastWasItem = true;
      blankSince = false;
    }

    void flushAll() {
      flushPara();
      flushItem();
      flushQuote();
      flushTable();
    }

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flushAll();
        blankSince = true;
        continue;
      }
      // A table: rows between pipes, the separator row left out.
      if (trimmed.startsWith('|') && trimmed.length > 1) {
        if (table.isEmpty) {
          flushPara();
          flushItem();
          flushQuote();
        }
        if (!_tableSeparator.hasMatch(trimmed)) {
          final inner = trimmed.substring(1, trimmed.endsWith('|') ? trimmed.length - 1 : trimmed.length);
          table.add([for (final c in inner.split('|')) c.trim()]);
        }
        continue;
      }
      flushTable();
      if (trimmed.startsWith('>')) {
        flushPara();
        flushItem();
        quote.add(trimmed.replaceFirst(RegExp(r'^>\s?'), ''));
        continue;
      }
      flushQuote();
      final h = _heading.firstMatch(line);
      if (h != null) {
        flushPara();
        flushItem();
        final level = h[1]!.length;
        final style = switch (level) {
          1 => TextStyle(fontSize: (size * 1.3).roundToDouble(), fontWeight: FontWeight.w700, height: 1.3, color: ui.text),
          2 => TextStyle(fontSize: (size * 1.15).roundToDouble(), fontWeight: FontWeight.w700, height: 1.3, color: ui.text),
          _ => TextStyle(fontSize: size, fontWeight: FontWeight.w600, height: 1.35, color: ui.text),
        };
        out.add(_Block(Text.rich(_inline(h[2]!, ui), style: style), _Kind.heading, level: level));
        lastWasItem = false;
        continue;
      }
      if (_rule.hasMatch(line)) {
        flushPara();
        flushItem();
        out.add(_Block(Container(height: 1, color: ui.line), _Kind.rule));
        lastWasItem = false;
        continue;
      }
      final m = _listItem.firstMatch(line);
      if (m != null) {
        flushPara();
        flushItem();
        final marker = m[2]!.replaceAll(')', '.');
        item = ((m[1]!.replaceAll('\t', '  ').length ~/ 2).clamp(0, 3), marker, StringBuffer(m[3]!));
        continue;
      }
      final it = item;
      if (it != null && RegExp(r'^\s').hasMatch(line)) {
        // It goes on: same item, no new line.
        it.$3.write(' $trimmed');
        continue;
      }
      flushItem();
      if (para.isEmpty) lastWasItem = false;
      para.add(line);
      blankSince = false;
    }
    flushAll();
    return out;
  }

  TextSpan _inline(String text, MikkyUi ui) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    final token = RegExp(
      r'\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\((https?://[^)\s]+)\)|(https?://[^\s)]+)|(?<![\w*])\*(?!\s)([^*]+?)\*(?![\w*])|(?<!\w)_(?!\s)([^_]+?)_(?!\w)',
    );
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      var at = 0;
      for (final m in token.allMatches(line)) {
        if (m.start > at) spans.add(TextSpan(text: line.substring(at, m.start)));
        if (m[1] != null) {
          spans.add(TextSpan(text: m[1], style: const TextStyle(fontWeight: FontWeight.w600)));
        } else if (m[2] != null) {
          // Code in a line: mono, a size smaller, on a light hollow.
          spans.add(TextSpan(text: ' ${m[2]} ', style: TextStyle(fontFamily: 'Geist Mono', fontSize: TextSize.small, color: ui.text, backgroundColor: ui.well)));
        } else if (m[6] != null || m[7] != null) {
          spans.add(TextSpan(text: m[6] ?? m[7], style: const TextStyle(fontStyle: FontStyle.italic)));
        } else {
          final url = m[4] ?? m[5]!;
          final tap = TapGestureRecognizer()..onTap = () => openUrl(url);
          _links.add(tap);
          spans.add(TextSpan(
            text: m[3] ?? url,
            style: TextStyle(color: ui.blue, decoration: TextDecoration.underline, decorationColor: ui.blue.withValues(alpha: .4)),
            recognizer: tap,
            mouseCursor: SystemMouseCursors.click,
          ));
        }
        at = m.end;
      }
      if (at < line.length) spans.add(TextSpan(text: line.substring(at)));
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return TextSpan(children: spans);
  }
}

/// A block of code in an answer: mono, on a light hollow, scrolling
/// sideways if long, with its language and a « Copier » button.
class CodeBlockView extends StatefulWidget {
  const CodeBlockView({super.key, required this.code, this.language = ''});

  final String code;
  final String language;

  @override
  State<CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<CodeBlockView> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      decoration: BoxDecoration(color: ui.well, borderRadius: BorderRadius.circular(Radii.lg)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 5, 5, 0),
          child: Row(children: [
            Expanded(child: Text(widget.language, style: uiText(TextSize.code, mono: true, color: ui.text3, height: 1.2))),
            Pressable(
              onTap: _copy,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  MikkyIcon(_copied ? 'check' : 'file', size: 12, color: ui.text3),
                  const SizedBox(width: 4),
                  Text(_copied ? 'Copié' : 'Copier', style: uiText(TextSize.caption, weight: FontWeight.w500, color: ui.text3, height: 1.2)),
                ]),
              ),
            ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 11),
          child: Text(widget.code, softWrap: false, style: uiText(TextSize.code + 1, mono: true, color: ui.text, height: 1.55)),
        ),
      ]),
    );
  }
}

/// A block of an answer: what it is ([level] for a title); for a list
/// item, [newList]: the first of its list.
class _Block {
  const _Block(this.child, this.kind, {this.newList = false, this.level = 0});

  final Widget child;
  final _Kind kind;
  final bool newList;
  final int level;
}
