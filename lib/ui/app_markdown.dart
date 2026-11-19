import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:paperplane/ui/theme/tokens.dart';

/// Renders the safe subset of Markdown Paperclip sends in approval and issue
/// bodies.
///
/// Supported: paragraphs, headings, ordered and unordered lists, block quotes,
/// fenced code, inline code, bold, italic, strikethrough, horizontal rules and
/// http(s) links. Raw HTML is shown as text, images become a placeholder, and
/// a parse failure falls back to plain text. Nothing here executes HTML or
/// loads a remote resource.
class AppMarkdown extends StatefulWidget {
  /// Creates the renderer for [data].
  const new(this.data, {this.onOpenLink, this.baseStyle, super.key});

  /// Markdown source.
  final String data;

  /// Called with an http(s) link. Without it, links render as plain text.
  final void Function(Uri uri)? onOpenLink;

  /// Overrides the body style.
  final TextStyle? baseStyle;

  @override
  State<AppMarkdown> createState() => _AppMarkdownState();
}

class _AppMarkdownState extends State<AppMarkdown> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final pp = context.pp;
    final style = widget.baseStyle ?? pp.text.body;
    final List<md.Node> nodes;
    try {
      nodes = md.Document().parse(widget.data);
    } on Object {
      return Text(widget.data, style: style);
    }
    final blocks = <Widget>[];
    for (final node in nodes) {
      final block = _block(node, style);
      if (block != null) blocks.add(block);
    }
    if (blocks.isEmpty) return Text(widget.data, style: style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.s3),
          blocks[i],
        ],
      ],
    );
  }

  Widget? _block(md.Node node, TextStyle style) {
    if (node is md.Text) {
      final text = _inlineSpan([node], style, block: true);
      return text == null ? null : Text.rich(text, style: style);
    }
    if (node is! md.Element) return null;
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'p':
        return _paragraph(children, style);
      case 'h1':
        return _heading(children, style, 1);
      case 'h2':
        return _heading(children, style, 2);
      case 'h3':
        return _heading(children, style, 3);
      case 'h4':
      case 'h5':
      case 'h6':
        return _heading(children, style, 4);
      case 'ul':
        return _list(children, style, ordered: false);
      case 'ol':
        return _list(children, style, ordered: true);
      case 'blockquote':
        return _quote(children, style);
      case 'pre':
      case 'code':
        return _codeBlock(node, style);
      case 'hr':
        return const Divider(height: Space.s5);
      case 'img':
        return _imagePlaceholder(node, style);
      case 'table':
        return _paragraph(children, style);
      case 'script':
      case 'style':
        return null;
      default:
        final inline = _inlineSpan(children, style, block: true);
        return inline == null ? null : Text.rich(inline, style: style);
    }
  }

  Widget _paragraph(List<md.Node> children, TextStyle style) {
    final span = _inlineSpan(children, style, block: true);
    return span == null
        ? const SizedBox.shrink()
        : Text.rich(span, style: style);
  }

  Widget _heading(List<md.Node> children, TextStyle style, int level) {
    final pp = context.pp;
    final heading = switch (level) {
      1 => pp.text.h.copyWith(fontSize: 24),
      2 => pp.text.h,
      3 => pp.text.h3,
      _ => pp.text.bodyStrong,
    };
    final span = _inlineSpan(children, heading, block: true);
    return Semantics(
      header: true,
      child: span == null
          ? const SizedBox.shrink()
          : Text.rich(span, style: heading),
    );
  }

  Widget _list(
    List<md.Node> children,
    TextStyle style, {
    required bool ordered,
  }) {
    final items = [
      for (final child in children)
        if (child is md.Element && child.tag == 'li') child,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : Space.s1),
            child: _listItem(items[i], style, ordered ? '${i + 1}.' : '•'),
          ),
      ],
    );
  }

  Widget _listItem(md.Element item, TextStyle style, String marker) {
    final children = item.children ?? const <md.Node>[];
    final inlineChildren = <md.Node>[];
    final nested = <Widget>[];
    for (final child in children) {
      if (child is md.Element && _isBlockTag(child.tag)) {
        final block = _block(child, style);
        if (block != null) nested.add(block);
      } else {
        inlineChildren.add(child);
      }
    }
    final span = _inlineSpan(inlineChildren, style, block: true);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 24, child: Text(marker, style: style)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (span != null) Text.rich(span, style: style),
              for (final block in nested) ...[
                const SizedBox(height: Space.s1),
                block,
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _quote(List<md.Node> children, TextStyle style) {
    final pp = context.pp;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: pp.line, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: Space.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final node in children) ?_block(node, style)],
        ),
      ),
    );
  }

  Widget _codeBlock(md.Element node, TextStyle style) {
    final pp = context.pp;
    final code = node.textContent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pp.panel,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(Space.s3),
        child: Text(code, style: pp.text.mono),
      ),
    );
  }

  Widget _imagePlaceholder(md.Element node, TextStyle style) {
    final alt = node.attributes['alt'];
    final label = alt == null || alt.isEmpty ? 'Image' : 'Image: $alt';
    return Text('[$label]', style: style.copyWith(fontStyle: FontStyle.italic));
  }

  /// Renders inline [nodes]. With [block], a null result means nothing to
  /// show; without it, an empty span is returned so parents always get one.
  TextSpan? _inlineSpan(
    List<md.Node> nodes,
    TextStyle style, {
    bool block = false,
  }) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      _addInline(node, style, spans, null);
    }
    if (spans.isEmpty) return block ? null : TextSpan(style: style);
    return TextSpan(style: style, children: spans);
  }

  void _addInline(
    md.Node node,
    TextStyle style,
    List<InlineSpan> out,
    GestureRecognizer? recognizer,
  ) {
    if (node is md.Text) {
      out.add(TextSpan(text: node.text, recognizer: recognizer));
      return;
    }
    if (node is! md.Element) return;
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'strong':
      case 'b':
        final bold = style.copyWith(
          fontWeight: FontWeight.w700,
          fontVariations: const [FontVariation('wght', 700)],
        );
        for (final child in children) {
          _addInline(child, bold, out, recognizer);
        }
      case 'em':
      case 'i':
        final italic = style.copyWith(fontStyle: FontStyle.italic);
        for (final child in children) {
          _addInline(child, italic, out, recognizer);
        }
      case 'del':
      case 's':
        final struck = style.copyWith(decoration: TextDecoration.lineThrough);
        for (final child in children) {
          _addInline(child, struck, out, recognizer);
        }
      case 'code':
        final code = style.copyWith(
          fontFamily: 'Menlo',
          fontFamilyFallback: const ['SF Mono', 'monospace'],
          backgroundColor: context.pp.panel,
        );
        out.add(
          TextSpan(text: node.textContent, style: code, recognizer: recognizer),
        );
      case 'a':
        final href = node.attributes['href'];
        final uri = href == null ? null : Uri.tryParse(href);
        if (widget.onOpenLink == null ||
            uri == null ||
            (uri.scheme != 'http' && uri.scheme != 'https')) {
          for (final child in children) {
            _addInline(child, style, out, recognizer);
          }
          return;
        }
        final linkStyle = style.copyWith(
          color: context.pp.accent,
          decoration: TextDecoration.underline,
        );
        final tap = TapGestureRecognizer()
          ..onTap = () => widget.onOpenLink?.call(uri);
        _recognizers.add(tap);
        for (final child in children) {
          _addInline(child, linkStyle, out, tap);
        }
      case 'br':
        out.add(TextSpan(text: '\n', recognizer: recognizer));
      case 'img':
        final alt = node.attributes['alt'];
        final label = alt == null || alt.isEmpty ? 'Image' : 'Image: $alt';
        out.add(TextSpan(text: '[$label]', recognizer: recognizer));
      default:
        for (final child in children) {
          _addInline(child, style, out, recognizer);
        }
    }
  }

  static bool _isBlockTag(String tag) => const {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'ul',
    'ol',
    'blockquote',
    'pre',
    'table',
    'hr',
  }.contains(tag);
}
