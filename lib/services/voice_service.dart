// lib/services/voice_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../config/env.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:universal_html/html.dart' as web;

class VoiceService {
  final _audioRecorder = AudioRecorder();
  final _amplitudeStreamController = StreamController<double>.broadcast();
  Timer? _amplitudeTimer;
  bool _isRecording = false;
  Timer? _silenceTimer;

  // Web specific variables
  dynamic _webMediaStream;
  dynamic _webMediaRecorder;
  final List<Uint8List> _webAudioChunks = [];
  
  bool get isRecording => _isRecording;
  Stream<double> get amplitudeStream => _amplitudeStreamController.stream;

  Future<void> initialize() async {
    try {
      if (kIsWeb) {
        _webMediaStream ??= await web.window.navigator.mediaDevices?.getUserMedia({
          'audio': true,
          'video': false
        });
      } else if (!await _checkPermission()) {
        throw Exception('需要麥克風權限');
      }
    } catch (e) {
      debugPrint('Error initializing recorder: $e');
      rethrow;
    }
  }

  Future<bool> _checkPermission() async {
    if (!await Permission.microphone.isGranted) {
      final status = await Permission.microphone.request();
      return status.isGranted;
    }
    return true;
  }

  Future<void> startRecording() async {
    try {
      if (kIsWeb) {
        await _startWebRecording();
      } else {
        await _startNativeRecording();
      }
      
      _isRecording = true;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      await _cleanup();
      rethrow;
    }
  }

  Future<void> _startWebRecording() async {
    _webAudioChunks.clear();
    
    if (_webMediaStream == null) {
      _webMediaStream = await web.window.navigator.mediaDevices?.getUserMedia({
        'audio': true,
        'video': false
      });
    }

    _webMediaRecorder = web.MediaRecorder(_webMediaStream, {
      'mimeType': 'audio/webm;codecs=opus'
    });

        _webMediaRecorder.addEventListener('dataavailable', (event) {
          if (event is web.BlobEvent && event.data != null) {
            final blob = event.data;
            if (blob == null) return;
            
            final reader = web.FileReader();
            // 確保 blob 不為 null 後再使用
            reader.readAsArrayBuffer(blob as web.Blob);
            reader.onLoadEnd.listen((e) {
              final result = reader.result;
              if (result is Uint8List) {
                _webAudioChunks.add(result);
              }
            });
          }
        });

    _webMediaRecorder.start(100);
    _startWebAmplitudeMonitoring();
  }

  Future<void> _startNativeRecording() async {
    if (!await _checkPermission()) {
      throw Exception('需要麥克風權限');
    }

    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 16 * 1000,
      ),
      path: tempPath,
    );
    
    _startNativeAmplitudeMonitoring();
  }

  void _startWebAmplitudeMonitoring() {
    _amplitudeTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (_isRecording) {
          final amplitude = math.Random().nextDouble() * 50 + 20;
          final normalizedLevel = math.min(1.0, amplitude / 100);
          _amplitudeStreamController.add(normalizedLevel);
        }
      },
    );
  }

  void _startNativeAmplitudeMonitoring() {
    _amplitudeTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) async {
        if (_isRecording) {
          final amplitude = await _audioRecorder.getAmplitude();
          final normalizedLevel = math.min(1.0, (amplitude.current ?? 0.0) / 100);
          _amplitudeStreamController.add(normalizedLevel);

          if (amplitude.current != null && amplitude.current! < 10) {
            _silenceTimer?.cancel();
            _silenceTimer = Timer(const Duration(seconds: 2), () {
              if (_isRecording) {
                stopRecording();
              }
            });
          } else {
            _silenceTimer?.cancel();
          }
        }
      },
    );
  }

  Future<void> _cleanup() async {
    _isRecording = false;
    _amplitudeTimer?.cancel();
    _silenceTimer?.cancel();
    
    if (kIsWeb) {
      _webMediaRecorder?.stop();
      try {
        final tracks = _webMediaStream?.getTracks() as List<dynamic>;
        for (final track in tracks) {
          track.stop();
        }
      } catch (e) {
        debugPrint('Error stopping web media tracks: $e');
      }
      _webMediaStream = null;
      _webMediaRecorder = null;
      _webAudioChunks.clear();
    } else {
      await _audioRecorder.stop();
    }
  }

  Future<(String, List<int>)?> stopRecording() async {
    if (!_isRecording) return null;
    final startTime = DateTime.now();
    debugPrint('${startTime.toString()} - 開始停止錄音');

    try {
      _silenceTimer?.cancel();
      _amplitudeTimer?.cancel();
      _isRecording = false;

      if (kIsWeb) {
        final audioData = await _stopWebRecording();
        return audioData != null ? ('', audioData) : null;
      } else {
        final path = await _audioRecorder.stop();
        if (path == null) {
          throw Exception('錄音保存失敗');
        }

        final file = await File(path).readAsBytes();
        final List<int> audioData = file.toList();
        
        final endTime = DateTime.now();
        debugPrint('錄音處理完成: ${endTime.difference(startTime).inMilliseconds}ms');
        
        return ('', audioData);
      }
    } catch (e) {
      debugPrint('停止錄音錯誤: $e');
      return null;
    }
  }

  Future<List<int>?> _stopWebRecording() async {
    if (_webMediaRecorder?.state != 'recording') return null;

    final completer = Completer<List<int>?>();
    
    void onStop(event) {
      _webMediaRecorder.removeEventListener('stop', onStop);
      
      if (_webAudioChunks.isEmpty) {
        completer.complete(null);
        return;
      }

      final blob = web.Blob(_webAudioChunks, 'audio/webm');
      final reader = web.FileReader();
      reader.readAsArrayBuffer(blob);
      reader.onLoadEnd.listen((event) {
        if (reader.result is Uint8List) {
          completer.complete((reader.result as Uint8List).toList());
        } else {
          completer.complete(null);
        }
      });
    }

    _webMediaRecorder.addEventListener('stop', onStop);
    _webMediaRecorder.stop();
    
    return completer.future;
  }

  Future<void> cancelRecording() async {
    await _cleanup();
  }

  Future<Stream<String>> sendToServer(List<int> audioData, {List<Map<String, String>>? dialogue}) async {
    try {
      final startTime = DateTime.now();
      debugPrint('${startTime.toString()} - 開始準備音頻發送，檔案大小: ${audioData.length} bytes');
      
      final request = http.MultipartRequest('POST', Uri.parse(Env.processAudioUrl))
        ..files.add(
          http.MultipartFile.fromBytes(
            'audio',
            audioData,
            filename: kIsWeb ? 'audio.webm' : 'audio.wav',
          ),
        )
        ..fields['dialogue'] = jsonEncode(dialogue ?? []);

      debugPrint('${DateTime.now()} - 開始發送請求');
      
      final streamedResponse = await request.send()
          .timeout(const Duration(seconds: 10));
      
      debugPrint('${DateTime.now()} - 開始接收響應');
      
      return streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
          
    } on TimeoutException catch (e) {
      debugPrint('請求超時: $e');
      rethrow;
    } catch (e) {
      debugPrint('發送音頻錯誤: $e');
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _cleanup();
    await _amplitudeStreamController.close();
  }
}