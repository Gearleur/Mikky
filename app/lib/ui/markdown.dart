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

/// The Markdown agents write in their answers, in simple: paragraphs with
/// **bold**, `code`, links ([text](url) and bare https://…) and « - »
/// lists; ``` blocks of code, each with its « Copier » button. Nothing else
/// is interpreted.
class AgentText extends StatefulWidget {
  const AgentText(this.text, {super.key});

  final String text;

  @override
  State<AgentText> createState() => _AgentTextState();
}

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
      if (before.isNotEmpty) blocks.addAll(_blocks(before, ui));
      final code = rest.substring(open.end, open.end + close.start).replaceAll(RegExp(r'^\n|\n$'), '');
      blocks.add(_Block(CodeBlockView(code: code, language: open[1] ?? '')));
      rest = rest.substring(open.end + close.end);
    }
    final after = rest.trim();
    if (after.isNotEmpty) blocks.addAll(_blocks(after, ui));
    if (blocks.length == 1) return blocks.single.child;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < blocks.length; i++)
        Padding(
          // Items of one list close together; everything else a bit apart.
          padding: EdgeInsets.only(top: i == 0 ? 0 : (blocks[i].item && blocks[i - 1].item && !blocks[i].newList ? 3 : 8)),
          child: blocks[i].child,
        ),
    ]);
  }

  static final _listItem = RegExp(r'^(\s*)([-*•]|\d+[.)])\s+(.*)$');

  /// Paragraphs and list items. A list item is a marker and its text, the
  /// text in a column of its own so a long item wraps under itself; a line
  /// that goes on an item (indented, no marker) joins it (user request,
  /// 2026-09-30).
  List<_Block> _blocks(String text, MikkyUi ui) {
    final out = <_Block>[];
    final para = <String>[];
    (int, String, StringBuffer)? item;
    var lastWasItem = false;
    var blankSince = false;
    void flushPara() {
      if (para.isEmpty) return;
      out.add(_Block(Text.rich(_inline(para.join('\n'), ui))));
      para.clear();
      lastWasItem = false;
    }

    void flushItem() {
      final it = item;
      if (it == null) return;
      final (level, marker, buf) = it;
      final bullet = !RegExp(r'^\d').hasMatch(marker);
      out.add(_Block(
        Padding(
          padding: EdgeInsets.only(left: 2 + level * 16.0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: bullet ? 14 : 20,
              child: Text(bullet ? '•' : marker, style: TextStyle(color: ui.text2, fontWeight: bullet ? FontWeight.w700 : FontWeight.w500)),
            ),
            Expanded(child: Text.rich(_inline(buf.toString(), ui))),
          ]),
        ),
        item: true,
        newList: !lastWasItem || blankSince,
      ));
      item = null;
      lastWasItem = true;
      blankSince = false;
    }

    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) {
        flushPara();
        flushItem();
        blankSince = true;
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
        it.$3.write(' ${line.trim()}');
        continue;
      }
      flushItem();
      if (para.isEmpty) lastWasItem = false;
      para.add(line.replaceFirst(RegExp(r'^#{1,6} '), ''));
      blankSince = false;
    }
    flushPara();
    flushItem();
    return out;
  }

  TextSpan _inline(String text, MikkyUi ui) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    final token = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\((https?://[^)\s]+)\)|(https?://[^\s)]+)');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      var at = 0;
      for (final m in token.allMatches(line)) {
        if (m.start > at) spans.add(TextSpan(text: line.substring(at, m.start)));
        if (m[1] != null) {
          spans.add(TextSpan(text: m[1], style: const TextStyle(fontWeight: FontWeight.w600)));
        } else if (m[2] != null) {
          spans.add(TextSpan(text: m[2], style: TextStyle(fontFamily: 'Geist Mono', fontSize: 12.5, backgroundColor: ui.track)));
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

/// A block of code in an answer: mono, on a hollow, scrolling sideways if
/// long, with its language and a « Copier » button.
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
      decoration: BoxDecoration(color: ui.island, borderRadius: BorderRadius.circular(12), border: Border.all(color: ui.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: ui.line))),
          child: Row(children: [
            Expanded(child: Text(widget.language, style: uiText(10.5, mono: true, color: ui.text3, height: 1.2))),
            Pressable(
              onTap: _copy,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  MikkyIcon(_copied ? 'check' : 'file', size: 12, color: ui.text2),
                  const SizedBox(width: 4),
                  Text(_copied ? 'Copié' : 'Copier', style: uiText(11, weight: FontWeight.w600, color: ui.text2, height: 1.2)),
                ]),
              ),
            ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
          child: Text(widget.code, softWrap: false, style: uiText(11.5, mono: true, color: ui.text, height: 1.45)),
        ),
      ]),
    );
  }
}

/// A block of an answer; [item]: a list item ([newList]: the first of its
/// list).
class _Block {
  const _Block(this.child, {this.item = false, this.newList = false});

  final Widget child;
  final bool item, newList;
}
