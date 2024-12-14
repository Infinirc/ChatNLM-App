// lib/widgets/markdown_content.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

class MarkdownContent extends StatelessWidget {
  final String content;
  final Color? textColor; // 新增文字顏色參數

  const MarkdownContent({
    super.key,
    required this.content,
    this.textColor, // 添加到建構子
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final defaultTextColor = isDarkMode ? Colors.white : const Color(0xFF2C2C2E);
    final currentTextColor = textColor ?? defaultTextColor;

    return MarkdownBody(
      data: content,
      selectable: true,
      builders: {
        'code': CodeElementBuilder(),
        'latex': LatexElementBuilder(),
      },
      inlineSyntaxes: [
        LatexSyntax(),
      ],
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: currentTextColor,
          fontSize: 16,
          height: 1.5,
          fontFamily: GoogleFonts.notoSans().fontFamily,
        ),
        code: TextStyle(
          color: currentTextColor,
          fontSize: 14,
          fontFamily: GoogleFonts.firaCode().fontFamily,
        ),
        blockquote: TextStyle(
          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
          fontSize: 16,
          height: 1.5,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
              width: 4,
            ),
          ),
        ),
        h1: TextStyle(
          color: currentTextColor,
          fontSize: 24,
          height: 1.5,
          fontWeight: FontWeight.bold,
          fontFamily: GoogleFonts.notoSans().fontFamily,
        ),
        h2: TextStyle(
          color: currentTextColor,
          fontSize: 20,
          height: 1.5,
          fontWeight: FontWeight.bold,
          fontFamily: GoogleFonts.notoSans().fontFamily,
        ),
        h3: TextStyle(
          color: currentTextColor,
          fontSize: 18,
          height: 1.5,
          fontWeight: FontWeight.bold,
          fontFamily: GoogleFonts.notoSans().fontFamily,
        ),
        listBullet: TextStyle(
          color: currentTextColor,
          fontSize: 16,
          fontFamily: GoogleFonts.notoSans().fontFamily,
        ),
      ),
    );
  }
}

class LatexSyntax extends md.InlineSyntax {
  LatexSyntax() : super(r'\$\$(.*?)\$\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final latex = match[1]!;
    parser.addNode(md.Element('latex', [md.Text(latex)]));
    return true;
  }
}

class LatexElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Builder(
      builder: (context) {
        // 使用 Theme 來獲取當前主題的文字顏色
        final textColor = Theme.of(context).textTheme.bodyLarge?.color ??
            (Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF2C2C2E));
        
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Math.tex(
            element.textContent,
            textStyle: TextStyle(
              color: textColor,
              fontSize: 16,
            ),
            mathStyle: MathStyle.display,
          ),
        );
      },
    );
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag == 'code') {
      String language = '';
      if (element.attributes['class'] != null) {
        language = element.attributes['class']!.replaceAll('language-', '');
      }

      return Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        language.toLowerCase(),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                          fontFamily: GoogleFonts.firaCode().fontFamily,
                        ),
                      ),
                      _CopyButton(content: element.textContent),
                    ],
                  ),
                ),
                if (language.isNotEmpty)
                  HighlightView(
                    element.textContent,
                    language: language,
                    theme: atomOneDarkTheme,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    textStyle: TextStyle(
                      fontFamily: GoogleFonts.firaCode().fontFamily,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: SelectableText(
                      element.textContent,
                      style: TextStyle(
                        fontFamily: GoogleFonts.firaCode().fontFamily,
                        fontSize: 14,
                        height: 1.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    return null;
  }
}

class _CopyButton extends StatefulWidget {
  final String content;

  const _CopyButton({
    required this.content,
  });

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _isCopied = false;

  void _copyContent() {
    Clipboard.setData(ClipboardData(text: widget.content));
    setState(() {
      _isCopied = true;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _isCopied = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _copyContent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isCopied ? Icons.check : Icons.copy_all_rounded,
            size: 16,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 4),
          Text(
            'Copy',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
              fontFamily: GoogleFonts.firaCode().fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}