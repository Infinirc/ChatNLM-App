// lib/screens/voice_input_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/voice_service.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:soundpool/soundpool.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'dart:collection';
import 'package:flutter/foundation.dart' show listEquals;

class VoiceInputScreen extends StatefulWidget {
  const VoiceInputScreen({super.key});

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen> with SingleTickerProviderStateMixin {
  bool _isClosed = false;
  int? _currentSoundId;
  int? _currentStreamId;
  final List<Map<String, String>> _dialogue = [];
  final List<List<int>> _pendingAudioList = [];
  bool _isLastAudioReceived = false;
  final VoiceService _voiceService = VoiceService();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animationController;
  late Soundpool _soundpool;
  List<double> _amplitudes = List<double>.filled(100, 0.0, growable: true);
  bool _isListening = false;
  String _transcribedText = '';
  String _responseText = '';
  String? _lastSentence;
  String? _tempFilePath;
  final Queue<List<int>> _audioQueue = Queue<List<int>>();
  bool _isPlayingAudio = false;
  bool _canStartNewRecording = false;
  
@override
void initState() {
  super.initState();
  _animationController = AnimationController(
    duration: const Duration(milliseconds: 1500),
    vsync: this,
  )..repeat();

  _soundpool = Soundpool.fromOptions(
    options: const SoundpoolOptions(
      streamType: StreamType.notification,
    ),
  );

  _initializeRecording();
}

  Future<void> _initializeRecording() async {
    try {
      await _voiceService.initialize();
      await _startRecording();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化录音失败: $e')),
        );
      }
    }
  }

@override
void dispose() {
  debugPrint('執行 dispose');
  
  // 確保音頻停止
  if (_currentStreamId != null) {
    try {
      _soundpool.stop(_currentStreamId!);
    } catch (e) {
      debugPrint('停止音頻時發生錯誤: $e');
    }
  }
  
  _scrollController.dispose();
  _animationController.dispose();
  _audioQueue.clear();
  _pendingAudioList.clear();
  _isPlayingAudio = false;
  
  _soundpool.release();
  _voiceService.dispose();
  _cleanupTempFile();
  
  super.dispose();
}
  void _cleanupTempFile() async {
    if (_tempFilePath != null) {
      try {
        final file = File(_tempFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error cleaning up temp file: $e');
      }
    }
  }
Future<void> _playNextPendingAudio() async {
  if (_isClosed) {  // 新增檢查
    debugPrint('頁面已關閉，停止播放音頻');
    _pendingAudioList.clear();
    _isPlayingAudio = false;
    return;
  }

  if (_pendingAudioList.isEmpty) {
    if (_isLastAudioReceived && !_isClosed) {  // 修改條件
      debugPrint('所有音頻播放完成，開始新的錄音');
      _isLastAudioReceived = false;
      await _startRecording();
    }
    return;
  }

  _isPlayingAudio = true;
  final audioData = _pendingAudioList.removeAt(0);
  final audioSizeKB = audioData.length / 1024;
  final startTime = DateTime.now();
  
  debugPrint('${startTime.toString()} - 開始播放 ${audioSizeKB.toStringAsFixed(2)} KB');

  try {
    if (_isClosed) return;  // 再次檢查，避免在加載過程中關閉

    final soundId = await _soundpool.load(
      Uint8List.fromList(audioData).buffer.asByteData()
    );
    _currentSoundId = soundId;

    if (_isClosed) {  // 加載後再次檢查
      await _soundpool.release();
      return;
    }

    debugPrint('${DateTime.now()} - 音頻已加載，開始播放');
    final streamId = await _soundpool.play(soundId);
    _currentStreamId = streamId;

    // 如果在等待過程中關閉了頁面，立即停止播放
    if (_isClosed) {
      if (_currentStreamId != null) {
        await _soundpool.stop(_currentStreamId!);
      }
      await _soundpool.release();
      return;
    }

    final expectedDuration = (audioData.length / (16000 * 2)) * 1000;
    final waitDuration = (expectedDuration * 0.52).toInt();
    await Future.delayed(Duration(milliseconds: waitDuration));

    await _soundpool.release();

    final endTime = DateTime.now();
    debugPrint('${endTime.toString()} - 播放完成，耗時: ${endTime.difference(startTime).inMilliseconds}ms');
    
    _isPlayingAudio = false;
    _currentStreamId = null;
    _currentSoundId = null;

    // 如果沒有關閉，繼續播放下一個音頻
    if (!_isClosed) {
      await _playNextPendingAudio();
    }
  } catch (e) {
    debugPrint('播放錯誤: $e');
    _isPlayingAudio = false;
    _currentStreamId = null;
    _currentSoundId = null;
    if (!_isClosed) {  // 只在沒有關閉的情況下繼續播放
      await _playNextPendingAudio();
    }
  }
}
void _processServerResponse(String line) {
  if (_isClosed) return;
    if (line.startsWith('data: ')) {
      try {
        final jsonStr = line.substring(6);
        if (jsonStr == '[DONE]') return;
        
        final data = json.decode(jsonStr);
        final now = DateTime.now();
        
        // 文字處理
        if (data['user_input'] != null) {
          setState(() {
            _transcribedText = data['user_input'];
          });
          _scrollToBottom();
          // 添加用戶輸入到對話歷史
          _dialogue.add({"role": "user", "content": data['user_input']});
        }
        
        if (data['token'] != null) {
          setState(() {
            _responseText += data['token'];
          });
          _scrollToBottom();
        }

        // 如果收到完整的響應，添加到對話歷史
        if (data['full_response'] != null) {
          _dialogue.add({"role": "assistant", "content": data['full_response']});
        }

        // 音频處理
        if (data['sentence'] != null && data['audio'] != null) {
          final sentence = data['sentence'] as String;
          debugPrint('${now.toString()} - 收到新音頻: $sentence');
          
          if (_lastSentence != sentence) {
            _lastSentence = sentence;
            final audioBytes = base64Decode(data['audio']);
            debugPrint('音頻大小: ${audioBytes.length} bytes');
            
            _pendingAudioList.add(audioBytes);
            if (!_isPlayingAudio) {
              _playNextPendingAudio();
            }
          }
        }

        if (data['all_audio_sent'] == true) {
          debugPrint('${now.toString()} - 收到全部完成信號');
          _isLastAudioReceived = true;
        }
        
      } catch (e) {
        debugPrint('處理服務器響應錯誤: $e');
      }
    }
}
Future<void> _playCurrentAudio(List<int> audioData) async {
    // 等待前一個音頻播放完成
    while (_isPlayingAudio) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    _isPlayingAudio = true;
    final startTime = DateTime.now();
    final audioSizeKB = audioData.length / 1024;
    debugPrint('${startTime.toString()} - 開始播放 ${audioSizeKB.toStringAsFixed(2)} KB');

    try {
      final soundId = await _soundpool.load(
        Uint8List.fromList(audioData).buffer.asByteData()
      );

      debugPrint('${DateTime.now()} - 音頻已加載，開始播放');
      await _soundpool.play(soundId);

      // 計算播放時間
      final expectedDuration = (audioData.length / (16000 * 2)) * 1000;
      final waitDuration = (expectedDuration * 0.52).toInt();
      await Future.delayed(Duration(milliseconds: waitDuration));

      await _soundpool.release();

      final endTime = DateTime.now();
      debugPrint('${endTime.toString()} - 播放完成，耗時: ${endTime.difference(startTime).inMilliseconds}ms');
      
      _isPlayingAudio = false;

      // 檢查是否是最後一個音頻，並且已收到全部完成信號
      if (_canStartNewRecording) {
        // 添加一個短暫延遲，確保音頻真的播放完成
        await Future.delayed(const Duration(milliseconds: 200));
        _canStartNewRecording = false;
        await _startRecording();
      }
      
    } catch (e) {
      debugPrint('播放錯誤: $e');
      _isPlayingAudio = false;
    }
}
Future<void> _playAudioDirectly(List<int> audioData) async {
    _isPlayingAudio = true;
    final startTime = DateTime.now();
    final audioSizeKB = audioData.length / 1024;
    debugPrint('${startTime.toString()} - 開始直接播放 ${audioSizeKB.toStringAsFixed(2)} KB');

    try {
      final soundId = await _soundpool.load(
        Uint8List.fromList(audioData).buffer.asByteData()
      );

      debugPrint('${DateTime.now()} - 音頻已加載，開始播放');
      await _soundpool.play(soundId);

      // 計算播放時間
      final expectedDuration = (audioData.length / (16000 * 2)) * 1000;
      final waitDuration = (expectedDuration * 0.52).toInt();
      await Future.delayed(Duration(milliseconds: waitDuration));

      await _soundpool.release();

      final endTime = DateTime.now();
      debugPrint('${endTime.toString()} - 播放完成，耗時: ${endTime.difference(startTime).inMilliseconds}ms');

      // 播放下一個
      if (_audioQueue.isNotEmpty) {
        final nextAudio = _audioQueue.removeFirst();
        await _playAudioDirectly(nextAudio);
      } else {
        _isPlayingAudio = false;
        if (_canStartNewRecording) {
          _canStartNewRecording = false;
          await _startRecording();
        }
      }
    } catch (e) {
      debugPrint('播放錯誤: $e');
      _isPlayingAudio = false;
    }
}
Future<void> _playNextAudio() async {
    if (_audioQueue.isEmpty) {
      debugPrint('${DateTime.now()} - 音頻隊列為空，結束播放');
      _isPlayingAudio = false;
      
      if (_canStartNewRecording) {
        debugPrint('開始新的錄音');
        _canStartNewRecording = false;
        await _startRecording();
      }
      return;
    }

    _isPlayingAudio = true;
    final audioData = _audioQueue.removeFirst();
    final audioSizeKB = audioData.length / 1024;
    final startTime = DateTime.now();
    debugPrint('${startTime.toString()} - 開始播放音頻片段 ${audioSizeKB.toStringAsFixed(2)} KB');

    try {
      // 計算播放時間
      final expectedDuration = (audioData.length / (16000 * 2)) * 1000;
      final waitDuration = (expectedDuration * 0.52).toInt(); // 使用 52% 的時間
      
      // 加載當前音頻
      final soundId = await _soundpool.load(
        Uint8List.fromList(audioData).buffer.asByteData()
      );
      
      // 提前加載下一段（但不播放）
      if (_audioQueue.isNotEmpty) {
        final nextAudioData = _audioQueue.first;
        await _soundpool.load(
          Uint8List.fromList(nextAudioData).buffer.asByteData()
        );
        debugPrint('下一段音頻已預加載');
      }

      debugPrint('${DateTime.now()} - 播放音頻 ${waitDuration}ms');
      await _soundpool.play(soundId);
      
      // 等待播放完成
      await Future.delayed(Duration(milliseconds: waitDuration));
      
      final endTime = DateTime.now();
      final playDuration = endTime.difference(startTime).inMilliseconds;
      debugPrint('${endTime.toString()} - 播放完成，耗時: ${playDuration}ms，剩餘: ${_audioQueue.length} 段');
      
      // 完全播放完後再釋放資源
      await _soundpool.release();
      
      // 播放下一段
      await _playNextAudio();
      
    } catch (e) {
      debugPrint('播放錯誤: $e');
      _isPlayingAudio = false;
      await _playNextAudio();
    }
}
Future<void> _playAudio(List<int> audioData) async {
    try {
      // 直接從記憶體播放，不需要寫入文件
      final soundId = await _soundpool.load(
        // 轉換音頻數據為 ByteData
        Uint8List.fromList(audioData).buffer.asByteData()
      );
      
      // 播放音頻
      await _soundpool.play(soundId);
      
      // 等待播放完成後清理
      await Future.delayed(const Duration(seconds: 1));
      await _soundpool.release();
      
      // 重新初始化 soundpool
      _soundpool = Soundpool.fromOptions(
        options: const SoundpoolOptions(
          streamType: StreamType.notification,
        ),
      );
      
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

// 需要修改的部分在 _startAmplitudeMonitoring 方法中的音量處理
Future<void> _startRecording() async {
  try {
    setState(() {
      _isListening = true;
      _lastSentence = null;
    });

    await _voiceService.startRecording();

    // 修改監聽器來安全地處理音量數據
    _voiceService.amplitudeStream.listen((amplitude) {
      if (mounted) {
        // 確保 amplitude 是一個有效的數字
        final double normalizedAmplitude = amplitude is double ? 
            amplitude : 
            (amplitude is num ? amplitude.toDouble() : 0.0);
            
        setState(() {
          _amplitudes = [..._amplitudes.sublist(1), normalizedAmplitude];
        });
      }
    });

  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('開始錄音失敗: $e')),
      );
    }
  }
}

Future<void> _stopRecording() async {
    if (!_isListening) return;
    debugPrint('停止錄音');

    setState(() {
      _isListening = false;
    });

    try {
      final result = await _voiceService.stopRecording();
      if (result != null) {
        final (transcription, wavFile) = result;
        debugPrint('錄音結束，清理狀態');
        
        // 重置狀態
        _isPlayingAudio = false;
        _pendingAudioList.clear();
        _isLastAudioReceived = false;
        _responseText = '';
        _lastSentence = null;
        
        debugPrint('發送音頻到服務器');
        final responseStream = await _voiceService.sendToServer(
          wavFile,
          dialogue: _dialogue, // 傳遞對話歷史
        );
        
        await for (final line in responseStream) {
          if (line.trim().isNotEmpty) {
            _processServerResponse(line.trim());
          }
        }
      }
    } catch (e) {
      debugPrint('停止錄音時發生錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('處理錄音失敗: $e')),
        );
      }
    }
}

@override
Widget build(BuildContext context) {
  return Container(
    color: Colors.black,
    child: SafeArea(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Spacer(),  // 使用 Spacer 來推動圓球到中間位置
                SizedBox(
                  height: 200,  // 恢復原來的高度
                  child: Center(
                    child: CustomPaint(
                      painter: WaveCirclePainter(
                        amplitudes: _amplitudes,
                        animation: _animationController,
                        isListening: _isListening,
                      ),
                      size: const Size(240, 240),  // 恢復原來的大小
                    ),
                  ),
                ),
                const Spacer(),  // 使用 Spacer 確保圓球垂直居中
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      children: [
if (_transcribedText.isNotEmpty)
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Colors.grey[900],
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      _transcribedText,
      textAlign: TextAlign.left,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        decoration: TextDecoration.none,
        decorationThickness: 0,
        decorationColor: Colors.transparent,
      ),
    ),
  ),
if (_responseText.isNotEmpty)
  Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.blue.withOpacity(0.2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      _responseText,
      textAlign: TextAlign.left,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        decoration: TextDecoration.none,
        decorationThickness: 0,
        decorationColor: Colors.transparent,
      ),
    ),
  ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildCircleButton(
                        icon: Icons.mic,
                        onTap: _isListening ? _stopRecording : _startRecording,
                        isActive: _isListening,
                      ),
                      _buildCircleButton(
                        icon: Icons.close,
                        onTap: _handleClose,
                        isActive: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}



void _scrollToBottom() {
  if (_scrollController.hasClients) {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }
}


void _handleClose() async {
  _isClosed = true;  // 確保在最開始就設置狀態
  debugPrint('開始關閉頁面流程');

  try {
    // 停止正在播放的音頻
    if (_currentStreamId != null) {
      debugPrint('停止當前播放音頻');
      try {
        await _soundpool.stop(_currentStreamId!);
      } catch (e) {
        debugPrint('停止音頻時發生錯誤: $e');
      }
    }

    // 停止錄音服務 (要在最前面停止)
    debugPrint('停止錄音服務');
    await _voiceService.cancelRecording();

    // 清理所有待播放音頻
    debugPrint('清理音頻隊列');
    _audioQueue.clear();
    _pendingAudioList.clear();
    _isPlayingAudio = false;
    _isLastAudioReceived = false;
    _canStartNewRecording = false;
    _currentStreamId = null;
    _currentSoundId = null;

    // 釋放音頻資源
    debugPrint('釋放音頻資源');
    await _soundpool.release();

    // 重置所有狀態
    if (mounted) {
      setState(() {
        _transcribedText = '';
        _responseText = '';
        _lastSentence = null;
        _dialogue.clear();
        _isListening = false;
      });
    }

    // 確保頁面關閉
    if (mounted) {
      Navigator.of(context).pop();
    }
  } catch (e) {
    debugPrint('關閉頁面時發生錯誤: $e');
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1C1C1E),
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.blue : Colors.white,
          size: 28,
        ),
      ),
    );
  }
}

class WaveCirclePainter extends CustomPainter {
  final List<double> amplitudes;
  final Animation<double> animation;
  final bool isListening;
  static const baseRadius = 120.0;
  static const numPoints = 180;
  
  // 添加振幅平滑處理
  late final List<double> _smoothedAmplitudes;

  WaveCirclePainter({
    required this.amplitudes,
    required this.animation,
    required this.isListening,
  }) : super(repaint: animation) {
    // 初始化時進行振幅平滑處理
    _smoothedAmplitudes = _smoothAmplitudes();
  }

  // 振幅平滑處理函數
  List<double> _smoothAmplitudes() {
    final smoothed = List<double>.filled(numPoints, 0.0);
    final windowSize = 5;  // 平滑窗口大小
    
    for (var i = 0; i < numPoints; i++) {
      var sum = 0.0;
      var count = 0;
      
      // 使用移動平均進行平滑
      for (var j = -windowSize; j <= windowSize; j++) {
        final idx = ((i + j) % amplitudes.length + amplitudes.length) % amplitudes.length;
        sum += amplitudes[idx];
        count++;
      }
      
      smoothed[i] = sum / count;
    }
    
    return smoothed;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    final gradient = ui.Gradient.linear(
      Offset(center.dx - baseRadius, center.dy),
      Offset(center.dx + baseRadius, center.dy),
      [
        Colors.blue.shade200,
        Colors.blue.shade400,
      ],
    );

    final paint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path();
    final animationValue = animation.value * math.pi * 2;

    if (isListening) {
      final points = List<Offset>.filled(numPoints, Offset.zero);
      final angleStep = (math.pi * 2) / numPoints;

      // 使用平滑後的振幅計算點位置
      for (var i = 0; i < numPoints; i++) {
        final angle = i * angleStep;
        final smoothedAmplitude = _smoothedAmplitudes[i];
        
        // 減小波動幅度並使用平滑振幅
        final wave = math.sin(angle * 4 + animationValue) * 0.03;
        final radius = baseRadius * (1 + smoothedAmplitude * 0.1 + wave);
        
        points[i] = Offset(
          center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle),
        );
      }

      // 繪製路徑
      path.moveTo(points[0].dx, points[0].dy);
      
      // 使用張力較小的曲線
      for (var i = 0; i < points.length; i++) {
        final point = points[i];
        final next = points[(i + 1) % points.length];
        final next2 = points[(i + 2) % points.length];
        
        final tension = 0.15;  // 降低張力
        final control1 = Offset(
          point.dx + (next.dx - point.dx) * tension,
          point.dy + (next.dy - point.dy) * tension,
        );
        final control2 = Offset(
          next.dx - (next2.dx - point.dx) * tension,
          next.dy - (next2.dy - point.dy) * tension,
        );
        
        path.cubicTo(
          control1.dx, control1.dy,
          control2.dx, control2.dy,
          next.dx, next.dy,
        );
      }
    } else {
      path.addOval(Rect.fromCenter(
        center: center,
        width: baseRadius * 2,
        height: baseRadius * 2,
      ));
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WaveCirclePainter oldDelegate) => true;
}