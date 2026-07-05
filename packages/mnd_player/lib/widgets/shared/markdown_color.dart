import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';

class ColorTagSyntax extends md.InlineSyntax {
  static const String tag = 'color';

  ColorTagSyntax()
    : super(
        r'\[color=(#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{8})\]([\s\S]*?)\[\/color\]',
        startCharacter: 0x5B, // [
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final colorValue = match.group(1);
    final content = match.group(2) ?? '';
    final children = parser.document.parseInline(content);
    final element = md.Element(tag, children);
    if (colorValue != null) {
      element.attributes['value'] = colorValue;
    }
    parser.addNode(element);
    return true;
  }
}

class ColorNode extends ElementNode {
  final Color color;

  ColorNode(this.color);

  @override
  TextStyle get style =>
      parentStyle?.merge(TextStyle(color: color)) ?? TextStyle(color: color);
}

class EmphasisNode extends ElementNode {
  @override
  TextStyle get style =>
      parentStyle?.merge(
        const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
      ) ??
      const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic);
}

MarkdownGenerator createColorMarkdownGenerator({
  EdgeInsets linesMargin = const EdgeInsets.symmetric(vertical: 2),
  RegExp? splitRegExp,
}) {
  return MarkdownGenerator(
    inlineSyntaxList: [ColorTagSyntax()],
    linesMargin: linesMargin,
    splitRegExp: splitRegExp,
    generators: [
      SpanNodeGeneratorWithTag(
        tag: ColorTagSyntax.tag,
        generator: (e, config, visitor) {
          final colorValue = e.attributes['value'];
          return ColorNode(_parseColor(colorValue));
        },
      ),
      SpanNodeGeneratorWithTag(
        tag: 'em',
        generator: (e, config, visitor) => EmphasisNode(),
      ),
    ],
  );
}

String preserveMarkdownHardLineBreaks(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  if (lines.length <= 1) return normalized;

  bool isBlockMarkdownLine(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) return false;
    return RegExp(
      r'^(#{1,6}\s|[-*+]\s|\d+\.\s|>\s|```|~~~|\|)',
    ).hasMatch(trimmed);
  }

  final out = <String>[];
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final isLast = i == lines.length - 1;
    if (isLast) {
      out.add(line);
      continue;
    }

    final isBlank = line.trim().isEmpty;
    final nextBlank = lines[i + 1].trim().isEmpty;
    final currentIsBlock = isBlockMarkdownLine(line);
    final nextIsBlock = isBlockMarkdownLine(lines[i + 1]);

    if (!isBlank && !nextBlank && !currentIsBlock && !nextIsBlock) {
      // Don't add hard break if line ends with a URL (causes visible backslash)
      final trimmedEnd = line.trimRight();
      final isUrl = RegExp(
        r'(https?://|www\.)[^\s]+$',
        caseSensitive: false,
      ).hasMatch(trimmedEnd);
      if (isUrl) {
        out.add(line);
      } else {
        out.add('$line\\');
      }
    } else {
      out.add(line);
    }
  }

  return out.join('\n');
}

Color _parseColor(String? colorStr) {
  if (colorStr == null) return Colors.white;
  if (colorStr.startsWith('#')) {
    String hex = colorStr.substring(1);
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    final value = int.tryParse(hex, radix: 16);
    if (value != null) {
      return Color(value);
    }
  }
  return Colors.white;
}
