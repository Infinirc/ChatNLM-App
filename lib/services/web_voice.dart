// lib/services/web_voice.dart
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:math' as math;
import 'platform_voice.dart';

class WebVoicePlatform implements VoicePlatform {
  html.MediaStream? _mediaStream;
  html.MediaRecorder? _mediaRecorder;
  List<Uint8List> _audioChunks = [];
  final _amplitudeController = StreamController<double>.broadcast();
  Timer? _amplitudeTimer;

  @override
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  @override
  Future<void> initialize() async {
    try {
      _mediaStream = await html.window.navigator.mediaDevices?.getUserMedia({
        'audio': true,
        'video': false
      });
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> startRecording() async {
    _audioChunks.clear();
    
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
    
    // Simulate amplitude for web platform
    _amplitudeTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (_mediaRecorder?.state == 'recording') {
          final randomAmplitude = math.Random().nextDouble() * 0.5 + 0.2;
          _amplitudeController.add(randomAmplitude);
        }
      },
    );
  }

  @override
  Future<List<int>?> stopRecording() async {
    _amplitudeTimer?.cancel();
    
    if (_mediaRecorder?.state != 'recording') return null;

    final completer = Completer<List<int>?>();
    
    void onStop(event) {
      _mediaRecorder!.removeEventListener('stop', onStop);
      
      if (_audioChunks.isEmpty) {
        completer.complete(null);
        return;
      }

      final blob = html.Blob(_audioChunks, 'audio/webm');
      final reader = html.FileReader();
      reader.readAsArrayBuffer(blob);
      reader.onLoadEnd.listen((event) {
        if (reader.result is Uint8List) {
          completer.complete((reader.result as Uint8List).toList());
        } else {
          completer.complete(null);
        }
      });
    }

    _mediaRecorder!.addEventListener('stop', onStop);
    _mediaRecorder!.stop();
    
    return completer.future;
  }

  @override
  Future<void> cancelRecording() async {
    _amplitudeTimer?.cancel();
    _mediaRecorder?.stop();
    _mediaStream?.getTracks().forEach((track) => track.stop());
    _mediaStream = null;
    _mediaRecorder = null;
    _audioChunks.clear();
  }

  @override
  Future<void> dispose() async {
    await cancelRecording();
    _amplitudeController.close();
  }
}

VoicePlatform createVoicePlatform() => WebVoicePlatform();