//lib/providers/chat_provider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../models/llm_model.dart';
import '../providers/conversation_provider.dart';
import '../providers/auth_provider.dart';
import '../config/env.dart';
import '../models/search_result.dart';
import 'package:http_parser/http_parser.dart';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../managers/message_rating_manager.dart';


class ImageData {
  final String path;
  final Uint8List bytes;
  final String fileName;
  final String? mimeType;  // 添加 MIME 类型

  ImageData({
    required this.path,
    required this.bytes,
    required this.fileName,
    this.mimeType = 'image/jpeg',  // 默认 MIME 类型
  });

  String get base64Image {
    final base64 = base64Encode(bytes);
    return 'data:${mimeType ?? 'image/jpeg'};base64,$base64';
  }
}

class ChatProvider with ChangeNotifier {



  // 添加图片数据缓存字段
  final Map<String, ImageData> _imageDataCache = {};

  // 添加图片数据相关方法
  void storeImageData(String path, ImageData data) {
    _imageDataCache[path] = data;
    notifyListeners();
  }

  ImageData? getImageData(String path) {
    return _imageDataCache[path];
  }


  WebSocketChannel? _channel;
  bool _isConnected = false;

  final List<Message> _messages = [];
  List<Message> get messages => _messages;
  
  String? _currentConversationId;
  String? get currentConversationId => _currentConversationId;
  
  LlmModel? _currentModel;
  LlmModel? get currentModel => _currentModel;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;
  
  bool _isLoadingMessages = false;
  bool get isLoadingMessages => _isLoadingMessages;
  
  StreamSubscription? _currentGeneration;
  late final BuildContext context;

  final String _baseUrl;
  final String _conversationUrl;
  final int _maxContextMessages = 10;
  final bool isTrialMode; // 新增試用模式標記

ChatProvider(
  BuildContext context, {
  String? baseUrl,
  String? conversationUrl,
  this.isTrialMode = false,
}) : _baseUrl = baseUrl ?? Env.llmApiUrl,
     _conversationUrl = conversationUrl ?? Env.conversationApiUrl {
  this.context = context;
  debugPrint('Initializing ChatProvider with:'
      '\nBase URL: $_baseUrl'
      '\nConversation URL: $_conversationUrl'
      '\nTrial Mode: $isTrialMode');
      
  // 在初始化時清理臨時文件
  _initCleanup();
}

Future<void> _connectWebSocket() async {
  try {
    // 先關閉舊的連接
    if (_channel != null) {
      _isConnected = false;
      await _channel!.sink.close();
      _channel = null;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    // 使用完整的 WebSocket URL
    final wsUrl = _baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$wsUrl/chat/completions');
    
    debugPrint('Connecting to WebSocket at: $uri');
    
    _channel = WebSocketChannel.connect(uri);
    _isConnected = true;
    debugPrint('WebSocket connected successfully');
  } catch (e) {
    debugPrint('WebSocket connection failed: $e');
    _isConnected = false;
    _channel = null;
  }
}

// 添加初始化清理方法
Future<void> _initCleanup() async {
  try {
    final tempDir = await getTemporaryDirectory();
    final files = tempDir.listSync();
    
    // 所有模式都清理圖片
    final imagePaths = files
      .whereType<File>()
      .where((file) => 
        file.path.toLowerCase().endsWith('.jpg') ||
        file.path.toLowerCase().endsWith('.jpeg') ||
        file.path.toLowerCase().endsWith('.png'))
      .map((file) => file.path)
      .toList();
    
    if (imagePaths.isNotEmpty) {
      await _cleanupTempImages(imagePaths);
      debugPrint('Cleaned up ${imagePaths.length} temporary image files');
    }
  } catch (e) {
    debugPrint('Error during initial cleanup: $e');
  }
}
Future<void> _cleanupTempImages(List<String>? imagePaths) async {
  if (imagePaths == null || imagePaths.isEmpty) return;

  for (final path in imagePaths) {
    try {
      final file = File(path);
      if (await file.exists()) {  // 移除 isTrialMode 判斷，所有模式都清理
        await file.delete();
        debugPrint('Cleaned up temp image: $path');
      }
    } catch (e) {
      debugPrint('Error cleaning up temp image: $e');
    }
  }
}

  Future<void> loadModels() async {
    try {
      final response = await http.get(
        Uri.parse(Env.modelsUrl),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['data'] != null && data['data'].isNotEmpty) {
          _currentModel = LlmModel.fromJson(data['data'][0]);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error loading models: $e');
    }
  }

  List<Map<String, dynamic>> _getContextMessages() {
    final List<Message> contextMessages = _messages
        .skip(2)
        .take(_maxContextMessages - 2)
        .toList()
        .reversed
        .toList();
    
    return contextMessages.map((msg) {
      return {
        'role': msg.role,
        'content': msg.content
      };
    }).toList();
  }

Future<void> _generateTitle(String userMessage, String aiResponse) async {
  if (_currentConversationId == null || _currentModel == null) {
    debugPrint('Cannot generate title: conversationId or model is null');
    return;
  }

  debugPrint('Starting title generation for conversation: $_currentConversationId');

  try {
    await _connectWebSocket();
    
    if (!_isConnected) {
      throw Exception('無法建立 WebSocket 連接');
    }

    final requestBody = {
      'model': _currentModel!.id,
      'messages': [
        {
          'role': 'user',
          'content': '''用5個字產生總結最後不要有標點符號
$userMessage
$aiResponse
用5個字產生聊天標題總結 最後不要有標點符號
'''
        }
      ],
      'max_tokens': 100,
      'stream': true,
    };

    _channel!.sink.add(jsonEncode(requestBody));
    String finalTitle = '';

    final completer = Completer<void>();
    StreamSubscription? subscription;

    subscription = _channel!.stream.listen(
      (data) {
        if (data is String) {
          if (data.startsWith('data: [DONE]')) {
            // 收到完成訊號，處理標題
            final trimmedTitle = finalTitle.trim();
            if (trimmedTitle.isNotEmpty) {
              _handleTitleComplete(trimmedTitle);
            }
            return;
          }
          
          if (data.startsWith('data: ')) {
            String jsonData = data.substring(6);
            try {
              final parsed = jsonDecode(jsonData);
              final content = parsed['choices'][0]['delta']['content'] ?? '';
              finalTitle += content;
            } catch (e) {
              debugPrint('Error parsing title chunk: $e');
            }
          }
        }
      },
      onDone: () async {
        subscription?.cancel();
        await _channel?.sink.close();
        _channel = null;
        _isConnected = false;
        completer.complete();
      },
      onError: (error) {
        debugPrint('WebSocket error in title generation: $error');
        subscription?.cancel();
        completer.completeError(error);
      },
      cancelOnError: true,
    );

    await completer.future;
  } catch (e) {
    debugPrint('Error generating title: $e');
  }
}
Future<void> _handleTitleComplete(String title) async {
  try {
    debugPrint('Handling title completion: $title');
    final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
    await conversationProvider.updateConversationTitle(
      _currentConversationId!,
      title
    );
    
    if (!isTrialMode) {
      final updatedConversation = conversationProvider.conversations
          .firstWhere((conv) => conv.id == _currentConversationId);
      await conversationProvider.setCurrentConversation(updatedConversation);
      await conversationProvider.loadConversations();
    }
    debugPrint('Title updated successfully: $title');
  } catch (e) {
    debugPrint('Error handling title completion: $e');
  }
}
  Future<void> clearMessages() async {
    debugPrint('Clearing messages');
    if (_isGenerating) {
      await stopGeneration();
    }
    
    _messages.clear();
    _currentConversationId = null;
    notifyListeners();
    debugPrint('Messages cleared');
  }

  Future<void> stopGeneration() async {
    debugPrint('Stopping generation');
    if (_currentGeneration != null) {
      await _currentGeneration!.cancel();
      _currentGeneration = null;
      
      if (_messages.isNotEmpty && !_messages[0].isComplete) {
        _messages[0] = _messages[0].copyWith(
          isComplete: true,
        );
      }
      
      _isGenerating = false;
      notifyListeners();
    }
  }


Future<void> loadConversationMessages(String conversationId) async {
  if (_isLoadingMessages) {
    return;
  }

  _isLoadingMessages = true;
  notifyListeners();

  try {
    if (_isGenerating) {
      await stopGeneration();
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    debugPrint('Loading messages for user: ${authProvider.userId}');
    
    _messages.clear();
    _currentConversationId = conversationId;
    
if (isTrialMode) {
  // 從本地加載消息
  final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
  final localMessages = conversationProvider.getLocalMessages(conversationId);
  if (localMessages != null && localMessages.isNotEmpty) {
    _messages.addAll(localMessages);
    // 確保按照時間戳降序排序（新的在前）
    _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    debugPrint('Loaded ${localMessages.length} messages from local storage');
  }
  notifyListeners();
  return;
}

    // 非試用模式的正常加載邏輯
    final response = await http.get(
      Uri.parse(Env.conversationMessagesUrl(conversationId)),
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': authProvider.userId ?? '',
      },
    );

if (response.statusCode == 200) {
  final List<dynamic> data = json.decode(response.body);
  debugPrint('Received ${data.length} messages from server');
  
  final Map<String, Message> latestMessages = {};
  
  for (var json in data) {
    debugPrint('Processing message: ${json['_id']} with rating: ${json['userRating']}');
    
    // 改進評分數據處理
if (json['userRating'] != null) {
  final userId = authProvider.userId ?? '';
  final currentVersion = json['currentVersion']?.toString() ?? '0';
  final ratingKey = '${userId}_$currentVersion';
  
  if (json['userRating'] is Map) {
    json['userRating'] = Map<String, dynamic>.from(json['userRating']);
    // 更新評分緩存
    Provider.of<MessageRatingManager>(context, listen: false).updateRatingCache(
      json['_id'],
      json['userRating']
    );
  } else if (json['userRating'] is String) {
    final ratingData = {
      ratingKey: json['userRating']
    };
    json['userRating'] = ratingData;
    Provider.of<MessageRatingManager>(context, listen: false).updateRatingCache(
      json['_id'],
      ratingData
    );
  }
  debugPrint('Processed rating data: ${json['userRating']}');
}

    final message = Message.fromJson(json);
    final key = '${message.role}_${message.timestamp.millisecondsSinceEpoch}';
    
    if (latestMessages.containsKey(key)) {
      final existingMessage = latestMessages[key]!;
      if (message.contentVersions != null && 
          message.currentVersion > (existingMessage.contentVersions?.length ?? -1)) {
        // 合併評分數據
        final Map<String, dynamic> mergedRatings = 
          Map<String, dynamic>.from(existingMessage.userRating ?? {});
        if (message.userRating != null) {
          mergedRatings.addAll(message.userRating!);
        }
        
        latestMessages[key] = message.copyWith(
          userRating: mergedRatings.isEmpty ? null : mergedRatings
        );
        debugPrint('Updated message with merged ratings: $mergedRatings');
      }
    } else {
      latestMessages[key] = message;
    }
  }

      final sortedMessages = latestMessages.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _messages.clear();
      _messages.addAll(sortedMessages);
      
      debugPrint('Loaded messages with ratings: ${_messages.map((m) => {
        'id': m.id,
        'userRating': m.userRating,
        'currentVersion': m.currentVersion
      }).toList()}');
    } else {
      throw Exception('Failed to load messages: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Error loading conversation messages: $e');
    _messages.clear();
    _currentConversationId = null;
    rethrow;
  } finally {
    _isLoadingMessages = false;
    notifyListeners();
  }
}
Future<Map<String, String>?> _uploadImage(String imagePath) async {
  try {
    debugPrint('Uploading image: $imagePath');
    
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_conversationUrl/upload')
    );

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    request.headers['x-user-id'] = authProvider.userId ?? '';

    if (kIsWeb && imagePath.startsWith('data:')) {
      // 解析 data URL
      final mimeTypeEnd = imagePath.indexOf(';base64,');
      if (mimeTypeEnd == -1) {
        throw Exception('Invalid image data URL');
      }

      final mimeType = imagePath.substring(5, mimeTypeEnd);
      final base64Data = imagePath.substring(mimeTypeEnd + 8);
      
      // 解码 base64 数据
      final bytes = base64Decode(base64Data);
      
      // 根据 MIME 类型确定文件扩展名
      String extension = 'jpg';
      if (mimeType.endsWith('/png')) {
        extension = 'png';
      } else if (mimeType.endsWith('/gif')) {
        extension = 'gif';
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'web_image.$extension',
          contentType: MediaType.parse(mimeType),
        )
      );

      debugPrint('Uploading web image:');
      debugPrint('MIME type: $mimeType');
      debugPrint('Extension: $extension');
      debugPrint('Data size: ${bytes.length} bytes');
    } else {
      // 移动平台处理方式不变
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imagePath,
          contentType: MediaType.parse('image/jpeg'),
        )
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      debugPrint('Upload success: ${data['url']}');
      return {
        'url': data['url'],
        'filename': data['filename']
      };
    } else {
      debugPrint('Upload failed with status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');
    }
    return null;
  } catch (e) {
    debugPrint('Error uploading image: $e');
    return null;
  }
}


Future<void> sendMessage(String content, {List<String>? images, bool useSearch = false}) async {
    if (_currentModel == null || (content.trim().isEmpty && (images == null || images.isEmpty))) {
      return;
    }

    final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
    
    // 確保有對話
    if (conversationProvider.currentConversation == null) {
      final conversation = await conversationProvider.createConversation('新對話');
      _currentConversationId = conversation.id;
      await conversationProvider.setCurrentConversation(conversation);
    } else {
      _currentConversationId = conversationProvider.currentConversation!.id;
    }

    _isGenerating = true;
    notifyListeners();

    List<Map<String, String>>? processedImages;
    List<Map<String, dynamic>> messageContent = [];
  
    // 處理圖片
// 處理圖片
if (images != null && images.isNotEmpty) {
  processedImages = [];
  for (final imagePath in images) {
    try {
      if (!isTrialMode) {
        debugPrint('Processing image for upload: $imagePath');
        
        // 添加重试逻辑
        int retries = 3;
        Map<String, String>? uploadResult;
        
        while (retries > 0 && uploadResult == null) {
          uploadResult = await _uploadImage(imagePath);
          if (uploadResult == null) {
            retries--;
            if (retries > 0) {
              await Future.delayed(Duration(seconds: 1));
            }
          }
        }

        if (uploadResult != null) {
          processedImages.add(uploadResult);
          debugPrint('Image processed successfully');

          // 为 LLM 准备图片内容
          if (kIsWeb) {
            messageContent.add({
              'type': 'image_url',
              'image_url': {'url': imagePath}
            });
          } else {
            final bytes = await File(imagePath).readAsBytes();
            final base64Image = base64Encode(bytes);
            messageContent.add({
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$base64Image'}
            });
          }
        } else {
          debugPrint('Failed to upload image after all retries');
        }
      } else {
        // 試用模式下的圖片處理
        if (kIsWeb) {
          processedImages.add({'url': imagePath});
          messageContent.add({
            'type': 'image_url',
            'image_url': {'url': imagePath}
          });
        } else {
          // 讀取本地圖片並轉換為 base64
          final bytes = await File(imagePath).readAsBytes();
          final base64Image = base64Encode(bytes);
          final base64Url = 'data:image/jpeg;base64,$base64Image';
          
          // 保存圖片數據到緩存
          storeImageData(imagePath, ImageData(
            path: imagePath,
            bytes: bytes,
            fileName: imagePath.split('/').last,
          ));
          
          processedImages.add({'url': base64Url});
          messageContent.add({
            'type': 'image_url',
            'image_url': {'url': base64Url}
          });
        }
        debugPrint('Trial mode: Image processed locally');
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
      if (isTrialMode) {
        // 試用模式下的錯誤處理
        processedImages.add({'url': imagePath});
        messageContent.add({
          'type': 'image_url',
          'image_url': {'url': imagePath}
        });
      }
    }
  }
}

    final trimmedContent = content.trim();
    if (trimmedContent.isNotEmpty) {
      messageContent.add({'type': 'text', 'text': trimmedContent});
    }

final timestamp = DateTime.now();

final userMessage = Message(
  id: isTrialMode ? 'trial_${DateTime.now().millisecondsSinceEpoch}' : null,
  content: trimmedContent,
  isUser: true,
  timestamp: DateTime.now(),
  role: 'user',
  images: processedImages,
);

_messages.insert(0, userMessage);
notifyListeners();

// 保存用戶消息
if (isTrialMode) {
  final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
  await conversationProvider.saveLocalMessage(_currentConversationId!, userMessage);
} else {
  await conversationProvider.saveMessage(userMessage);
}
    // 創建 AI 消息
    final aiMessage = Message(
      id: isTrialMode ? 'trial_${DateTime.now().millisecondsSinceEpoch}' : null,
      content: useSearch ? '🔍 正在分析問題...' : '',
      isUser: false,
      timestamp: DateTime.now(),
      isComplete: false,
      role: 'assistant',
    );
    _messages.insert(0, aiMessage);
    notifyListeners();

    try {
      List<SearchResult>? searchResults;
      if (useSearch) {
        // 更新搜尋狀態並生成關鍵字
        _messages[0] = _messages[0].copyWith(
          content: '🔍 正在生成搜尋關鍵字...',
        );
        notifyListeners();

        final searchKeywords = await _generateSearchKeywords(trimmedContent);
        _messages[0] = _messages[0].copyWith(
          content: '🔍 搜尋關鍵字：$searchKeywords\n正在搜尋相關資訊...',
        );
        notifyListeners();

        // 執行搜尋
        searchResults = await _performSearch(searchKeywords);
        _messages[0] = _messages[0].copyWith(
          content: '📚 找到 ${searchResults.length} 個相關結果\n正在整理資訊...',
        );
        notifyListeners();
      }

      // 處理搜尋結果
      String systemPrompt = '';
      if (searchResults != null && searchResults.isNotEmpty) {
        systemPrompt = '我找到了一些相關資訊：\n\n';
        for (var result in searchResults) {
          if (result.title.isNotEmpty && result.content.isNotEmpty) {
            systemPrompt += '來源: ${result.title}\n';
            systemPrompt += '內容: ${result.content}\n\n';
          }
        }
        
        searchResults = searchResults.where((result) => 
          result.title.isNotEmpty && 
          result.content.isNotEmpty
        ).toList();
        
        systemPrompt += '根據以上資訊，參考多一點資訊，來回答你的問題，且要是最新資訊，詳細一點可以列點：\n';

        _messages[0] = _messages[0].copyWith(
          content: '🤔 正在根據搜尋結果生成回答...',
          searchResults: searchResults,
        );
        notifyListeners();
      }

      // 建立 WebSocket 連接
      await _connectWebSocket();
      
      if (!_isConnected) {
        throw Exception('無法建立 WebSocket 連接');
      }

      final requestBody = {
        'model': _currentModel!.id,
        'messages': [
          if (systemPrompt.isNotEmpty)
            {
              'role': 'system',
              'content': systemPrompt,
            },
          ...(_getContextMessages()),
          {
            'role': 'user',
            'content': messageContent,
          }
        ],
        'max_tokens': 1000,
        'stream': true,
      };

      // 發送消息到 WebSocket
      _channel!.sink.add(jsonEncode(requestBody));
      String currentContent = '';

      // 設置 WebSocket 監聽器
_currentGeneration = _channel!.stream.listen(
  (data) {
    if (data is String) {
      if (data.startsWith('data: [DONE]')) {
        // 收到完成信號，處理消息完成邏輯
        _handleMessageComplete(currentContent, searchResults);
        return;
      }
      
      if (data.startsWith('data: ')) {
        String jsonData = data.substring(6);
        try {
          final parsed = jsonDecode(jsonData);
          final content = parsed['choices'][0]['delta']['content'] ?? '';
          currentContent += content;
          
          _messages[0] = _messages[0].copyWith(
            content: currentContent,
            searchResults: searchResults,
          );
          notifyListeners();
        } catch (e) {
          debugPrint('Error parsing WebSocket data: $e');
        }
      }
    }
  },
  onDone: () {
    debugPrint('WebSocket connection closed');
    _isGenerating = false;
    _currentGeneration = null;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    notifyListeners();
  },
  onError: (error) {
    debugPrint('WebSocket error: $error');
    _messages[0] = _messages[0].copyWith(
      content: '❌ WebSocket 連接錯誤',
      isComplete: true,
    );
    _isGenerating = false;
    notifyListeners();
  },
  cancelOnError: true,
);
      
    } catch (e) {
      debugPrint('Error in send message: $e');
      _messages[0] = _messages[0].copyWith(
        content: '❌ 處理訊息時發生錯誤',
        isComplete: true,
      );
      _isGenerating = false;
      notifyListeners();
    }
}

Future<void> _handleMessageComplete(String currentContent, List<SearchResult>? searchResults) async {
  try {
    debugPrint('Handling message completion');
    
    // 更新 AI 消息內容
    final aiMessage = _messages[0].copyWith(
      content: currentContent,
      isComplete: true,  // 確保設置完成狀態
      searchResults: searchResults,
    );
    
    // 試用模式下的處理
    if (isTrialMode) {
      _messages[0] = aiMessage;  // 直接更新當前消息狀態
      
      final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
      await conversationProvider.saveLocalMessage(
        _currentConversationId!,
        aiMessage
      );
      
      final localMessages = conversationProvider.getLocalMessages(_currentConversationId!);
      if (localMessages != null) {
        _messages.clear();
        _messages.addAll(localMessages);
        _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      
      // 確保立即更新 UI 顯示完成狀態
      _isGenerating = false;
      notifyListeners();
    } else {
      // 非試用模式邏輯保持不變
      final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
      final response = await http.post(
        Uri.parse('${_conversationUrl}/conversations/$_currentConversationId/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-user-id': Provider.of<AuthProvider>(context, listen: false).userId ?? '',
        },
        body: json.encode(aiMessage.toJson()),
      );
      
      if (response.statusCode == 200) {
        final savedMessageData = json.decode(response.body);
        final savedMessage = Message.fromJson(savedMessageData);
        _messages[0] = savedMessage.copyWith(
          content: currentContent,
          isComplete: true,
          searchResults: searchResults,
        );
        
        final messageRatingManager = Provider.of<MessageRatingManager>(context, listen: false);
        messageRatingManager.updateMessageId(aiMessage.id, savedMessage.id);
      }
      
      await conversationProvider.saveMessage(_messages[0]);
    }

    // 確保關閉 WebSocket 連接
    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
      _isConnected = false;
    }
    
    // 生成標題
    if (_messages.length == 2) {
      debugPrint('Preparing to generate title');
      await Future.delayed(const Duration(milliseconds: 200));
      if (_messages[0].isComplete && _messages[1].content.isNotEmpty) {
        debugPrint('Starting title generation');
        await _generateTitle(
          _messages[1].content,
          currentContent,
        );
      }
    }

  } catch (e) {
    debugPrint('Error in _handleMessageComplete: $e');
    // 確保錯誤情況下也更新狀態
    _messages[0] = _messages[0].copyWith(
      isComplete: true,
      content: currentContent,
    );
  } finally {
    // 確保在所有情況下都重置狀態
    _isGenerating = false;
    notifyListeners();
  }
}
Future<String> _generateSearchKeywords(String content) async {
  try {
    await _connectWebSocket();
    
    if (!_isConnected) {
      throw Exception('無法建立 WebSocket 連接');
    }

    final requestBody = {
      'model': _currentModel!.id,
      'messages': [
        {
          'role': 'system',
          'content': '你是一個搜尋關鍵字生成器。請根據用戶的問題生成最適合的搜尋關鍵字。只需要返回關鍵字，不要有任何額外說明。'
        },
        {
          'role': 'user',
          'content': content,
        }
      ],
      'max_tokens': 50,
      'temperature': 0.5,
      'stream': true,  // Add this explicitly
    };

    _channel!.sink.add(jsonEncode(requestBody));
    final completer = Completer<String>();
    String keywords = '';
    StreamSubscription? subscription;

    subscription = _channel!.stream.listen(
      (data) {
        if (data is String) {
          if (data.startsWith('data: [DONE]')) {
            // Handle completion correctly
            subscription?.cancel();
            _channel?.sink.close();
            _channel = null;
            _isConnected = false;
            completer.complete(keywords.trim());
            return;
          }
          
          if (data.startsWith('data: ')) {
            String jsonData = data.substring(6);
            try {
              final parsed = jsonDecode(jsonData);
              final content = parsed['choices'][0]['delta']['content'] ?? '';
              keywords += content;
            } catch (e) {
              debugPrint('Error parsing keywords chunk: $e');
            }
          }
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(keywords.trim());
        }
        subscription?.cancel();
        _channel?.sink.close();
        _channel = null;
        _isConnected = false;
      },
      onError: (error) {
        debugPrint('WebSocket error in keywords generation: $error');
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
        subscription?.cancel();
      },
      cancelOnError: true,
    );

    return await completer.future;
  } catch (e) {
    debugPrint('Error generating search keywords: $e');
    return content;
  }
}

Future<List<SearchResult>> _performSearch(String query) async {
  try {
    debugPrint('Performing search with query: $query');
    
    final url = Uri.parse('${Env.searchApiUrl}/search').replace(
      queryParameters: {
        'q': query,
        'format': 'json',
      },
    );
    
    debugPrint('Search URL: $url');

    final Map<String, String> headers;
    if (kIsWeb) {
      // Web 平台的特定設置
      headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        // 添加 CORS 相關標頭
        'Origin': Uri.base.origin,
        'Access-Control-Allow-Origin': '*',
      };
    } else {
      // iOS/Android 平台的設置
      headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
    }

    final response = await http.get(
      url,
      headers: headers,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('Search request timed out');
        return http.Response('{"results":[]}', 408);
      },
    );

    if (response.statusCode == 200) {
      debugPrint('Search response body: ${response.body}');
      final data = jsonDecode(response.body);
      
      if (data['results'] != null) {
        final results = (data['results'] as List)
          .where((result) => 
            result['url'] != null && 
            result['title'] != null && 
            result['content'] != null &&
            result['content'].toString().isNotEmpty &&
            result['engine'] != null)
          .map((result) {
            try {
              final uri = Uri.parse(result['url'] as String);
              return <String, dynamic>{
                'url': result['url'] as String,
                'title': result['title'] as String,
                'content': result['content'] as String,
                'engine': result['engine'] as String,
                'engines': (result['engines'] ?? [result['engine']]) as List<dynamic>,
                'favicon': 'https://www.google.com/s2/favicons?domain=${uri.host}',
                if (result['thumbnail'] != null) 'thumbnail': result['thumbnail'] as String,
              };
            } catch (e) {
              debugPrint('Error processing result: $e');
              return null;
            }
          })
          .where((result) => result != null)
          .map((enrichedResult) => SearchResult.fromJson(enrichedResult!))
          .toList();

        debugPrint('Found ${results.length} search results');

        if (_messages.isNotEmpty) {
          _messages[0] = _messages[0].copyWith(
            searchResults: results,
          );
          notifyListeners();
        }

        return results;
      }
    } else {
      debugPrint('Search failed with status code: ${response.statusCode}');
      debugPrint('Response headers: ${response.headers}');
      debugPrint('Response body: ${response.body}');
    }
    
    return [];
  } catch (e, stack) {
    debugPrint('Error performing search: $e');
    debugPrint('Stack trace: $stack');
    
    if (_messages.isNotEmpty) {
      _messages[0] = _messages[0].copyWith(
        searchResults: const [],
      );
      notifyListeners();
    }
    
    return [];
  }
}
void switchMessageVersion(String messageId, int version) {
  final index = _messages.indexWhere((msg) => msg.id == messageId);
  if (index != -1 && _messages[index].contentVersions != null) {
    if (version >= 0 && version < _messages[index].contentVersions!.length) {
      // 保存當前的評分數據
      final currentRatings = _messages[index].userRating;
      
      _messages[index] = _messages[index].copyWith(
        content: _messages[index].contentVersions![version],
        currentVersion: version,
        userRating: currentRatings,  // 保持評分數據
      );
      notifyListeners();
      
      // 保存到服務器
      try {
        final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
        conversationProvider.saveMessage(_messages[index]);
      } catch (e) {
        debugPrint('Error saving message version: $e');
      }
    }
  }
}
Future<void> regenerateResponse(String messageId) async {
  if (_isGenerating || _currentConversationId == null) {
    return;
  }

  try {
    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index < 0 || _messages[index].isUser) {
      return;
    }

    // 保存當前的評分狀態
    final currentRating = _messages[index].userRating;
    final currentVersion = _messages[index].currentVersion.toString();
    final String? oldVersionRating = currentRating?[currentVersion];

    // 準備版本數據
    List<String> newVersions;
    if (_messages[index].contentVersions == null) {
      newVersions = [_messages[index].content];
    } else {
      newVersions = List<String>.from(_messages[index].contentVersions!);
    }

    String? userContent;
    List<Map<String, dynamic>>? userMessageContent;
    for (int i = index + 1; i < _messages.length; i++) {
      if (_messages[i].isUser) {
        userContent = _messages[i].content;
        
        if (_messages[i].images != null && _messages[i].images!.isNotEmpty) {
          userMessageContent = [];
          for (var image in _messages[i].images!) {
            try {
              final bytes = await File(image['url']!).readAsBytes();
              final base64Image = base64Encode(bytes);
              userMessageContent.add({
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,$base64Image'}
              });
            } catch (e) {
              debugPrint('Error processing image: $e');
            }
          }
        }
        break;
      }
    }

    if (userContent == null) return;

    if (userContent.trim().isNotEmpty) {
      userMessageContent ??= [];
      userMessageContent.add({'type': 'text', 'text': userContent.trim()});
    }

    _isGenerating = true;
    _messages[index] = _messages[index].copyWith(
      content: '',
      isComplete: false,
      contentVersions: newVersions,
      currentVersion: newVersions.length,
      userRating: currentRating,
    );
    notifyListeners();

    try {
      // 建立 WebSocket 連接
      await _connectWebSocket();
      
      if (!_isConnected) {
        throw Exception('無法建立 WebSocket 連接');
      }

      final requestBody = {
        'model': _currentModel!.id,
        'messages': [
          ...(_getContextMessages()),
          {
            'role': 'user',
            'content': userMessageContent
          }
        ],
        'max_tokens': 1000,
        'stream': true,
      };

      // 發送消息到 WebSocket
      _channel!.sink.add(jsonEncode(requestBody));
      String currentContent = '';

      // 設置 WebSocket 監聽器
      _currentGeneration = _channel!.stream.listen(
        (data) {
          if (data is String) {
            if (data.startsWith('data: [DONE]')) {
              // 收到完成信號，更新版本並保存
              _handleRegenerationComplete(
                index,
                currentContent,
                newVersions,
                currentRating,
                oldVersionRating
              );
              return;
            }
            
            if (data.startsWith('data: ')) {
              String jsonData = data.substring(6);
              try {
                final parsed = jsonDecode(jsonData);
                final content = parsed['choices'][0]['delta']['content'] ?? '';
                currentContent += content;
                
                _messages[index] = _messages[index].copyWith(
                  content: currentContent,
                  userRating: currentRating,
                );
                notifyListeners();
              } catch (e) {
                debugPrint('Error parsing WebSocket data: $e');
              }
            }
          }
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          _isGenerating = false;
          _currentGeneration = null;
          _channel?.sink.close();
          _channel = null;
          _isConnected = false;
          notifyListeners();
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _handleRegenerationError(
            index,
            '❌ WebSocket 連接錯誤',
            newVersions,
            currentRating
          );
        },
        cancelOnError: true,
      );

    } catch (e) {
      debugPrint('Error in regeneration: $e');
      _handleRegenerationError(
        index,
        '❌ 重新生成過程中發生錯誤',
        newVersions,
        currentRating
      );
    }
  } catch (e) {
    debugPrint('Error in regenerate response: $e');
    _isGenerating = false;
    notifyListeners();
  }
}

// 處理重新生成完成
Future<void> _handleRegenerationComplete(
  int index,
  String currentContent,
  List<String> versions,
  Map<String, dynamic>? currentRating,
  String? oldVersionRating
) async {
  try {
    versions.add(currentContent);
    
    debugPrint('Completing regeneration with ratings: $currentRating');
    
    // 處理評分數據
    Map<String, dynamic>? updatedRating = currentRating;
    if (currentRating != null) {
      updatedRating = Map<String, dynamic>.from(currentRating);
      // 為新版本設置舊版本的評分
      if (oldVersionRating != null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final newVersionKey = '${authProvider.userId}_${versions.length - 1}';
        updatedRating[newVersionKey] = oldVersionRating;
      }
    }
    
    _messages[index] = _messages[index].copyWith(
      content: currentContent,
      isComplete: true,
      contentVersions: versions,
      currentVersion: versions.length - 1,
      userRating: updatedRating,
    );

    if (!isTrialMode) {
      debugPrint('Saving regenerated message with ratings: $updatedRating');
      final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
      await conversationProvider.saveMessage(_messages[index]);

      // 延遲以確保伺服器處理完成
      await Future.delayed(const Duration(milliseconds: 200));
      
      // 重新載入以確保數據同步
      final response = await http.get(
        Uri.parse('${_conversationUrl}/conversations/$_currentConversationId/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-user-id': Provider.of<AuthProvider>(context, listen: false).userId ?? '',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> messages = json.decode(response.body);
        debugPrint('Reloaded messages after regeneration');
        
        final savedMessage = messages.firstWhere(
          (msg) => 
            msg['content'] == currentContent && 
            msg['role'] == 'assistant' &&
            msg['currentVersion'] == versions.length - 1,
          orElse: () => null,
        );

        if (savedMessage != null) {
          debugPrint('Found saved message with ratings: ${savedMessage['userRating']}');
          _messages[index] = Message.fromJson(savedMessage).copyWith(
            content: currentContent,
            isComplete: true,
            contentVersions: versions,
            currentVersion: versions.length - 1,
            userRating: savedMessage['userRating'] ?? updatedRating,
          );
        }
      }
    }

    if (index == 0 && _messages.length == 2) {
      debugPrint('Regenerating title after response update');
      await Future.delayed(const Duration(milliseconds: 100));
      await _generateTitle(
        _messages[1].content,
        _messages[0].content,
      );
    }
  } catch (e) {
    debugPrint('Error handling regeneration complete: $e');
  } finally {
    _isGenerating = false;
    _currentGeneration = null;
    notifyListeners();
  }
}

// 處理重新生成錯誤
Future<void> _handleRegenerationError(
  int index,
  String errorMessage,
  List<String> versions,
  Map<String, dynamic>? currentRating
) async {
  try {
    _messages[index] = _messages[index].copyWith(
      content: errorMessage,
      isComplete: true,
      contentVersions: versions,
      currentVersion: versions.length - 1,
      userRating: currentRating,
    );

    if (!isTrialMode) {
      final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
      await conversationProvider.saveMessage(_messages[index]);
    }
  } catch (e) {
    debugPrint('Error handling regeneration error: $e');
  } finally {
    _isGenerating = false;
    _currentGeneration = null;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    notifyListeners();
  }
}

  Future<void> switchConversation(String conversationId) async {
    try {
      debugPrint('Switching to conversation: $conversationId');
      
      if (_currentConversationId == conversationId && _messages.isNotEmpty) {
        debugPrint('Already on conversation $conversationId, skipping switch');
        return;
      }
      
      if (_isGenerating) {
        await stopGeneration();
      }
      
      await loadConversationMessages(conversationId);
    } catch (e) {
      debugPrint('Error switching conversation: $e');
      await clearMessages();
      rethrow;
    }
  }

Future<void> createNewConversation() async {
  try {
    final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
    await clearMessages();
    
    final conversation = await conversationProvider.createConversation('新對話');
    _currentConversationId = conversation.id;
    
    if (!isTrialMode) {
      await conversationProvider.setCurrentConversation(conversation);
    }
    
    debugPrint('Created new conversation with ID: $_currentConversationId (Trial Mode: $isTrialMode)');
  } catch (e) {
    debugPrint('Error creating new conversation: $e');
    rethrow;
  }
}

@override
void dispose() {
  _imageDataCache.clear();
  
  // 試用模式和非試用模式都清理圖片
  final allImagePaths = _messages
    .expand((msg) => (msg.images ?? [])
      .map((img) => img['url'] as String)
      .where((path) => 
        path != null && 
        !path.startsWith('/uploads/') &&
        !path.startsWith('data:') // 排除 base64 格式的圖片
      ))
    .toList();

  _cleanupTempImages(allImagePaths);
  
  _channel?.sink.close();
  _channel = null;
  _isConnected = false;
  
  _currentGeneration?.cancel();
  _messages.clear();
  _currentConversationId = null;
  _isGenerating = false;
  _isLoadingMessages = false;
  super.dispose();
}

}