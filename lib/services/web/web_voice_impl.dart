// lib/services/web/web_voice_impl.dart
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class WebVoiceImpl {
  html.MediaStream? _mediaStream;
  html.MediaRecorder? _mediaRecorder;
  List<Uint8List> _audioChunks = [];
  final _amplitudeController = StreamController<double>.broadcast();
  
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  Future<void> initialize() async {
    try {
      _mediaStream = await html.window.navigator.mediaDevices?.getUserMedia({
        'audio': true,
        'video': false
      });
    } catch (e) {
      debugPrint('Web voice initialization error: $e');
      rethrow;
    }
  }

  Future<void> startRecording() async {
    _audioChunks = [];
    
    if (_mediaStream == null) {
      await initialize();
    }

    _mediaRecorder = html.MediaRecorder(_mediaStream!, {
      'mimeType': 'audio/webm;codecs=opus'
    });

    _mediaRecorder!.addEventListener('dataavailable', (event) {
      if (event is html.BlobEvent && event.data != null) {
        final reader = html.FileReader();
        reader.readAsArrayBuffer(event.data!);
        reader.onLoadEnd.listen((e) {
          if (reader.result is Uint8List) {
            _audioChunks.add(reader.result as Uint8List);
          }
        });
      }
    });

    _mediaRecorder!.start(100);
    
    // Simulate amplitude for web
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_mediaRecorder?.state == 'recording') {
        // Generate random amplitude between 0 and 1
        _amplitudeController.add(0.5);
      } else {
        timer.cancel();
      }
    });
  }

  Future<Uint8List?> stopRecording() async {
    if (_mediaRecorder?.state != 'recording') return null;

    final completer = Completer<Uint8List?>();
    
    _mediaRecorder!.addEventListener('stop', (event) {
      if (_audioChunks.isEmpty) {
        completer.complete(null);
        return;
      }

      // Combine all chunks
      final blob = html.Blob(_audioChunks, 'audio/webm');
      final reader = html.FileReader();
      reader.readAsArrayBuffer(blob);
      reader.onLoadEnd.listen((event) {
        if (reader.result is Uint8List) {
          completer.complete(reader.result as Uint8List);
        } else {
          completer.complete(null);
        }
      });
    });

    _mediaRecorder!.stop();
    return completer.future;
  }

  Future<void> dispose() async {
    _mediaStream?.getTracks().forEach((track) => track.stop());
    _mediaStream = null;
    _mediaRecorder = null;
    _audioChunks = [];
    await _amplitudeController.close();
  }
}