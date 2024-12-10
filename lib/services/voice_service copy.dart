// lib/services/voice_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../config/env.dart';
import 'package:path_provider/path_provider.dart';
class VoiceService {
  final _audioRecorder = AudioRecorder();
  final _amplitudeStreamController = StreamController<double>.broadcast();
  Timer? _amplitudeTimer;
  bool _isRecording = false;
  Timer? _silenceTimer;
  
  bool get isRecording => _isRecording;
  Stream<double> get amplitudeStream => _amplitudeStreamController.stream;

  Future<void> initialize() async {
    try {
      // 檢查權限
      if (!await _checkPermission()) {
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
  if (!await _checkPermission()) {
    throw Exception('需要麥克風權限');
  }

  try {
    // 獲取臨時目錄路徑
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.wav';

    // 設置錄音配置
    await _audioRecorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 16 * 1000, // 16 kbps
      ),
      path: tempPath, // 提供保存路徑
    );
    
    _isRecording = true;

    // 開始監測音量
    _amplitudeTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) async {
        if (_isRecording) {
          final amplitude = await _audioRecorder.getAmplitude();
          final normalizedLevel = math.min(1.0, (amplitude.current as double) / 100);
          _amplitudeStreamController.add(normalizedLevel);

          // 檢測靜音
          if (amplitude.current < 10) {
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

  } catch (e) {
    debugPrint('Error starting recording: $e');
    await _cleanupOnError();
    rethrow;
  }
}

  Future<void> _cleanupOnError() async {
    _isRecording = false;
    _amplitudeTimer?.cancel();
    await _audioRecorder.stop();
  }

Future<(String transcription, List<int> audioData)?> stopRecording() async {
    if (!_isRecording) return null;
    final startTime = DateTime.now();
    debugPrint('${startTime.toString()} - 開始停止錄音');

    try {
      _silenceTimer?.cancel();
      _amplitudeTimer?.cancel();
      _isRecording = false;

      final path = await _audioRecorder.stop();
      if (path == null) {
        throw Exception('錄音保存失敗');
      }

      debugPrint('${DateTime.now()} - 錄音停止完成，開始讀取文件');
      final file = await File(path).readAsBytes();
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;
      debugPrint('錄音處理完成:');
      debugPrint('- 耗時: ${duration}ms');
      debugPrint('- 檔案大小: ${file.length} bytes');
      debugPrint('- 檔案路徑: $path');
      
      return ('', file.toList());

    } catch (e) {
      debugPrint('停止錄音錯誤: $e');
      return null;
    }
}

  Future<void> cancelRecording() async {
    _silenceTimer?.cancel();
    _amplitudeTimer?.cancel();
    
    if (!_isRecording) return;

    try {
      await _audioRecorder.stop();
      _isRecording = false;
    } catch (e) {
      debugPrint('Error canceling recording: $e');
    }
  }

Future<Stream<String>> sendToServer(List<int> wavFile, {List<Map<String, String>>? dialogue}) async {
    try {
      final startTime = DateTime.now();
      debugPrint('${startTime.toString()} - 開始準備音頻發送，檔案大小: ${wavFile.length} bytes');
      
      final request = http.MultipartRequest('POST', Uri.parse(Env.processAudioUrl))
        ..files.add(
          http.MultipartFile.fromBytes(
            'audio',
            wavFile,
            filename: 'audio.wav',
          ),
        )
        ..fields['dialogue'] = jsonEncode(dialogue ?? []);

      debugPrint('${DateTime.now()} - 開始發送請求');
      
      final streamedResponse = await request.send()
          .timeout(const Duration(seconds: 10));
      
      final responseStartTime = DateTime.now();
      debugPrint('${responseStartTime.toString()} - 開始接收響應');
      
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
    _silenceTimer?.cancel();
    _amplitudeTimer?.cancel();
    _amplitudeStreamController.close();
    await _audioRecorder.stop();
  }
}