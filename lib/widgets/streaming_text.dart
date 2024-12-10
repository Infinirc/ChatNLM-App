// lib/widgets/streaming_text.dart
import 'package:flutter/material.dart';
import 'dart:async';

class StreamingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final Duration streamDuration;
  final bool streamEnabled;
  final int? maxLength; // 新增最大長度限制

  const StreamingText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
    this.streamDuration = const Duration(milliseconds: 50),
    this.streamEnabled = false,
    this.maxLength, // 新增
  });

  @override
  State<StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<StreamingText> {
  String _displayText = '';
  Timer? _timer;
  int _currentIndex = 0;
  bool _isStreaming = false;

  // 處理文字截斷
  String get _processedText {
    if (widget.maxLength != null && widget.text.length > widget.maxLength!) {
      // 如果超過最大長度，保留maxLength-1個字符，最後加上"..."
      return '${widget.text.substring(0, widget.maxLength! - 1)}...';
    }
    return widget.text;
  }

  @override
  void initState() {
    super.initState();
    if (widget.streamEnabled) {
      _startStreaming();
    } else {
      _displayText = _processedText; // 使用處理後的文字
    }
  }

  @override
  void didUpdateWidget(StreamingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      if (widget.streamEnabled) {
        setState(() {
          _displayText = '';
          _currentIndex = 0;
          _isStreaming = true;
        });
        _startStreaming();
      } else {
        setState(() {
          _displayText = _processedText; // 使用處理後的文字
          _isStreaming = false;
        });
      }
    }
  }

  void _startStreaming() {
    _timer?.cancel();
    final textToStream = _processedText; // 使用處理後的文字
    if (_currentIndex < textToStream.length) {
      _isStreaming = true;
      _timer = Timer.periodic(widget.streamDuration, (timer) {
        if (_currentIndex < textToStream.length) {
          setState(() {
            _displayText = textToStream.substring(0, _currentIndex + 1);
            _currentIndex++;
          });
        } else {
          setState(() {
            _isStreaming = false;
          });
          timer.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            _displayText,
            style: widget.style,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
          ),
        ),
        if (_isStreaming)
          Text(
            '▋',
            style: widget.style?.copyWith(
              color: Colors.grey[400],
            ),
          ),
      ],
    );
  }
}