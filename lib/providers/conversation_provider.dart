//lib/providers/conversation_provider.dart
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/conversation.dart';
import '../models/message.dart';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class ConversationGroup {
  final String title;
  final List<Conversation> conversations;

  ConversationGroup({
    required this.title,
    required this.conversations,
  });
}

class ConversationProvider with ChangeNotifier {
  final Map<String, List<Message>> _localMessages = {};
  final String baseUrl;
  final String userId;
  final bool isTrialMode;
  List<Conversation> _conversations = [];
  List<Conversation> _filteredConversations = [];
  Conversation? _currentConversation;
  String _searchQuery = '';
  bool _isTitleUpdating = false;
  bool _hasMoreData = true;
  bool get hasMoreData => _hasMoreData;
  int _currentPage = 1;
  final int _pageSize = 20;
  int _nextPage = 1;

  // WebSocket 相關屬性
  WebSocketChannel? _channel;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  static const _reconnectDelay = Duration(seconds: 5);
  static const _pingInterval = Duration(seconds: 30);

  // Getters
  List<Conversation> get conversations => _searchQuery.isEmpty 
    ? List.unmodifiable(_conversations)
    : List.unmodifiable(_filteredConversations);
    
  Conversation? get currentConversation => _currentConversation;
  String get searchQuery => _searchQuery;
  bool get isTitleUpdating => _isTitleUpdating;

  ConversationProvider({
    required this.baseUrl,
    required this.userId,
    this.isTrialMode = false,
  }) {
    if (!isTrialMode) {
      _connectWebSocket();
    }
  }

  // Methods
  void setSearchQuery(String query) {
    _searchQuery = query.toLowerCase();
    _filterConversations();
    notifyListeners();
  }

  void _filterConversations() {
    if (_searchQuery.isEmpty) {
      _filteredConversations = [];
      return;
    }

    _filteredConversations = _conversations
        .where((conv) => conv.title.toLowerCase().contains(_searchQuery))
        .toList();
  }
void _connectWebSocket() {
  if (_isConnecting || isTrialMode || userId.isEmpty) return;
  _isConnecting = true;
  
  try {
    final wsUrl = baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    // 將 userId 加入 URL 參數中而不是 headers
    final uri = Uri.parse('$wsUrl/ws').replace(
      queryParameters: {
        'userId': userId,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      }
    );
    
    debugPrint('Connecting to WebSocket at: $uri');
    
    _channel = WebSocketChannel.connect(
      uri,
      protocols: const ['websocket'],
    );

    _channel?.stream.listen(
      _handleWebSocketMessage,
      onError: (error) {
        debugPrint('WebSocket error occurred: $error');
        _handleWebSocketError(error);
      },
      onDone: () {
        debugPrint('WebSocket connection closed normally');
        _handleWebSocketDone();
      },
      cancelOnError: false,  // 改為 false 以允許重試
    );

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      try {
        if (_channel?.sink != null) {
          _channel?.sink.add(json.encode({
            'type': 'ping',
            'userId': userId,
            'timestamp': DateTime.now().millisecondsSinceEpoch
          }));
          debugPrint('Sent ping message');
        }
      } catch (e) {
        debugPrint('Error sending ping: $e');
        _scheduleReconnect();
      }
    });

    debugPrint('WebSocket initialized successfully');
    _isConnecting = false;
  } catch (e) {
    debugPrint('WebSocket connection error: $e');
    _scheduleReconnect();
  }
}
// 在 ConversationProvider 類的 _handleWebSocketMessage 方法中添加 message_rated 處理
void _handleWebSocketMessage(dynamic message) {
  try {
    final data = json.decode(message as String);
    debugPrint('Received WebSocket message type: ${data['type']}');
    
    switch (data['type']) {
      case 'message_rated':
        if (_currentConversation?.id == data['conversationId']) {
          debugPrint('Received message rating update: ${data['userRating']}');
          setCurrentConversation(_currentConversation!);
        }
        loadConversations(); // 添加重新加載
        break;

      case 'conversation_created':
        if (data['conversation'] != null) {
          loadConversations(); // 改為直接重新加載
          debugPrint('Reloading conversations after new conversation created');
        }
        break;

      case 'message_created':
      case 'message_updated':
        if (_currentConversation?.id == data['conversationId']) {
          setCurrentConversation(_currentConversation!);
        }
        loadConversations(); // 添加重新加載
        break;
        
      case 'conversation_updated':
        if (data['conversation'] != null) {
          loadConversations(); // 改為直接重新加載
          debugPrint('Reloading conversations after conversation update');
        }
        break;
          
      case 'conversation_deleted':
        final conversationId = data['conversationId'];
        if (conversationId != null) {
          loadConversations(); // 改為直接重新加載
          debugPrint('Reloading conversations after conversation deletion');
        }
        break;

      case 'connected':
        debugPrint('WebSocket connection established');
        loadConversations(); // 連接成功後立即加載
        break;
          
      case 'pong':
        debugPrint('Received pong from server');
        break;

      default:
        debugPrint('Unhandled WebSocket message type: ${data['type']}');
        loadConversations(); // 未知消息類型也重新加載
        break;
    }
  } catch (e) {
    debugPrint('Error handling WebSocket message: $e');
  }
}
  void _handleWebSocketError(error) {
    debugPrint('WebSocket error: $error');
    _scheduleReconnect();
  }

void _handleWebSocketDone() {
  debugPrint('WebSocket connection closed');
  _scheduleReconnect();
  
  // 只在非試用模式且列表為空時重新加載
  if (!isTrialMode && _conversations.isEmpty) {
    loadConversations();
  }
}

  void _scheduleReconnect() {
    _isConnecting = false;
    _closeWebSocket();
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!isTrialMode && userId.isNotEmpty) {
        _connectWebSocket();
      }
    });
  }

  void _closeWebSocket() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _channel?.sink.close(status.goingAway);
    _channel = null;
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _closeWebSocket();
    clearLocalMessages();  // 清理本地消息
    super.dispose();
  }

List<ConversationGroup> getGroupedConversations() {
  // 獲取當前本地時間，並設置為當天的開始時間（00:00:00）
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  final twoDaysAgo = DateTime(now.year, now.month, now.day - 2);



  final conversationsToGroup = _searchQuery.isEmpty 
      ? _conversations 
      : _filteredConversations;

  final todayConversations = <Conversation>[];
  final yesterdayConversations = <Conversation>[];
  final twoDaysAgoConversations = <Conversation>[];
  final olderConversations = <Conversation>[];

  for (var conversation in conversationsToGroup) {
    // 將 UTC 時間轉換為本地時間
    final localTime = conversation.lastModified.toLocal();
    // 獲取對話日期的 00:00:00 時間點
    final conversationDate = DateTime(
      localTime.year,
      localTime.month,
      localTime.day,
    );



    // 直接比較日期
    final diffFromToday = today.difference(conversationDate).inDays;
    
    if (diffFromToday == 0) {
      todayConversations.add(conversation);
     
    } else if (diffFromToday == 1) {
      yesterdayConversations.add(conversation);
  
    } else if (diffFromToday == 2) {
      twoDaysAgoConversations.add(conversation);

    } else {
      olderConversations.add(conversation);

    }
  }

  // 排序函數
  void sortConversations(List<Conversation> conversations) {
    conversations.sort((a, b) => b.lastModified.compareTo(a.lastModified));
  }

  final groups = <ConversationGroup>[];

  if (todayConversations.isNotEmpty) {
    sortConversations(todayConversations);
    groups.add(ConversationGroup(
      title: '今天',
      conversations: todayConversations,
    ));
  }

  if (yesterdayConversations.isNotEmpty) {
    sortConversations(yesterdayConversations);
    groups.add(ConversationGroup(
      title: '昨天',
      conversations: yesterdayConversations,
    ));
  }

  if (twoDaysAgoConversations.isNotEmpty) {
    sortConversations(twoDaysAgoConversations);
    groups.add(ConversationGroup(
      title: '前天',
      conversations: twoDaysAgoConversations,
    ));
  }

  if (olderConversations.isNotEmpty) {
    sortConversations(olderConversations);
    groups.add(ConversationGroup(
      title: '更早',
      conversations: olderConversations,
    ));
  }



  return groups;
}
  Future<void> saveLocalMessage(String conversationId, Message message) async {
    if (!isTrialMode) return;
    
    if (!_localMessages.containsKey(conversationId)) {
      _localMessages[conversationId] = [];
    }
    _localMessages[conversationId]!.add(message);
    notifyListeners();
  }
  List<Message>? getLocalMessages(String conversationId) {
    return _localMessages[conversationId];
  }

    void clearLocalMessages() {
    _localMessages.clear();
    notifyListeners();
  }
Future<void> clearAllConversations() async {
  try {
    debugPrint('Clearing all conversations for user: $userId');
    
    // 試用模式直接清除本地數據
    if (isTrialMode) {
      _conversations.clear();
      _currentConversation = null;
      _filteredConversations.clear();
      _currentPage = 1;
      _hasMoreData = true;
      notifyListeners();
      return;
    }

    final response = await http.delete(
      Uri.parse('$baseUrl/conversations'),
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': userId,
      },
    );

    if (response.statusCode == 200) {
      _conversations.clear();
      _currentConversation = null;
      _filteredConversations.clear();
      _currentPage = 1;
      _hasMoreData = true;
      notifyListeners();
    } else {
      throw Exception('Failed to clear conversations: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Error clearing all conversations: $e');
    rethrow;
  }
}
// 在 ConversationProvider 中添加或修改
bool _isLoadingMore = false;
bool get isLoadingMore => _isLoadingMore;

Future<bool> loadMoreConversations() async {
  if (!_hasMoreData || _isLoadingMore) return false;

  try {
    _isLoadingMore = true;
    notifyListeners();
    
    debugPrint('Loading more conversations - page: $_nextPage');
    
    // 獲取當前最舊的對話日期
    final oldestDate = _conversations.isNotEmpty 
        ? _conversations.last.lastModified 
        : DateTime.now();

    debugPrint('Current oldest date: ${oldestDate.toIso8601String()}');
    
    final response = await http.get(
      Uri.parse('$baseUrl/conversations').replace(
        queryParameters: {
          'page': _nextPage.toString(),
          'pageSize': '20',
          'lastModifiedBefore': oldestDate.toIso8601String(), // 添加時間過濾參數
        }
      ),
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': userId,
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      debugPrint('載入更多對話: 第 $_nextPage 頁，${data.length} 條記錄');
      
      if (data.isEmpty) {
        _hasMoreData = false;
        notifyListeners();
        return false;
      }

      final newConversations = data
        .map((json) => Conversation.fromJson(json))
        .toList();
      
      // 檢查是否有新的（更舊的）對話
      if (_conversations.isNotEmpty) {
        final oldestExisting = _conversations.last.lastModified;
        newConversations.removeWhere(
          (conv) => conv.lastModified.isAfter(oldestExisting)
        );
      }

      // 如果篩選後還有新對話，添加到列表
      if (newConversations.isNotEmpty) {
        _conversations.addAll(newConversations);
        _conversations.sort((a, b) => b.lastModified.compareTo(a.lastModified));
        
        debugPrint('Added ${newConversations.length} older conversations');
        debugPrint('New oldest date: ${_conversations.last.lastModified.toIso8601String()}');
        
        // 檢查新數據中最舊的記錄日期
        final newOldestDate = newConversations.last.lastModified;
        debugPrint('Checking for more data before: ${newOldestDate.toIso8601String()}');
        
        // 如果獲取到了完整的一頁數據，假設還有更多
        _hasMoreData = newConversations.length >= 20;
      } else {
        _hasMoreData = false;
      }

      _nextPage++;
      _filterConversations();
      notifyListeners();
      
      return newConversations.isNotEmpty;
    } else {
      throw Exception('Failed to load more conversations: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Error loading more conversations: $e');
    rethrow;
  } finally {
    _isLoadingMore = false;
    notifyListeners();
  }
}

Future<void> loadConversations() async {
  if (userId.isEmpty) {
    debugPrint('User ID is empty, skipping load conversations');
    return;
  }

  try {
    debugPrint('Loading initial conversations for userId: $userId');
    _nextPage = 1;
    _hasMoreData = true;
    _isLoadingMore = false;
    
    final response = await http.get(
      Uri.parse('$baseUrl/conversations').replace(
        queryParameters: {
          'page': '1',
          'pageSize': '20'  // 使用較小的頁面大小以減少重複
        }
      ),
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': userId,
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      debugPrint('Loaded ${data.length} conversations');
      
      _conversations = data
        .map((json) => Conversation.fromJson(json))
        .toList()
        ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
      
      // 只要第一頁有數據，就假定可能有更多
      _hasMoreData = data.length >= 20;
      _nextPage = 2;
      
      _filterConversations();
      
      if (_conversations.isNotEmpty) {
        debugPrint('Latest conversation date: ${_conversations.first.lastModified.toIso8601String()}');
        debugPrint('Oldest conversation date: ${_conversations.last.lastModified.toIso8601String()}');
      }
      
      notifyListeners();
    } else {
      throw Exception('Failed to load conversations: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Error loading conversations: $e');
    rethrow;
  }
}

  Future<Conversation> createConversation(String title) async {
    if (userId.isEmpty) {
      debugPrint('Creating conversation failed: Empty userId');
      throw Exception('User ID is required');
    }

    try {
      // 試用模式創建本地臨時對話
      if (isTrialMode) {
        final conversationId = 'trial_${DateTime.now().millisecondsSinceEpoch}';
        final conversation = Conversation(
          id: conversationId,
          title: title,
          createdAt: DateTime.now(),
          lastModified: DateTime.now(),
          localImages: [],
        );
        
        _conversations.insert(0, conversation);
        _currentConversation = conversation;
        _filterConversations();
        
        // 初始化這個對話的本地消息列表
        _localMessages[conversationId] = [];
        
        notifyListeners();
        debugPrint('Created new trial conversation: ${conversation.id}');
        return conversation;
      }

    debugPrint('Creating conversation with userId: $userId');
    final response = await http.post(
      Uri.parse('$baseUrl/conversations'),
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': userId,
      },
      body: json.encode({
        'title': title,
        'createdAt': DateTime.now().toIso8601String(),
        'lastModified': DateTime.now().toIso8601String(),
      }),
    );

    if (response.statusCode == 200) {
      final conversation = Conversation.fromJson(json.decode(response.body));
      _conversations.insert(0, conversation);
      _currentConversation = conversation;
      _filterConversations();
      notifyListeners();
      debugPrint('Created new conversation: ${conversation.id}');
      return conversation;
    } else {
      final error = 'Failed to create conversation: ${response.statusCode}\nResponse: ${response.body}';
      debugPrint(error);
      throw Exception(error);
    }
  } catch (e) {
    debugPrint('Error creating conversation: $e');
    rethrow;
  }
}

Future<void> updateConversationTitle(String conversationId, String newTitle) async {
  debugPrint('Updating conversation $conversationId title to: $newTitle (Trial Mode: $isTrialMode)');
  try {
    _isTitleUpdating = true;
    notifyListeners();

    // 1. 先找到並更新對話
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      // 先設置空標題來啟動 StreamingText 的動畫
      _conversations[index] = _conversations[index].copyWith(
        title: '',
        lastModified: DateTime.now(),
      );
      if (_currentConversation?.id == conversationId) {
        _currentConversation = _conversations[index];
      }
      notifyListeners();
      
      // 等待一下確保 UI 更新
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 設置完整標題
      final updatedConversation = _conversations[index].copyWith(
        title: newTitle,
        lastModified: DateTime.now(),
      );
      _conversations[index] = updatedConversation;

      if (_currentConversation?.id == conversationId) {
        _currentConversation = updatedConversation;
      }

      // 3. 非試用模式才調用 API
      if (!isTrialMode) {
        final response = await http.patch(
          Uri.parse('$baseUrl/conversations/$conversationId'),
          headers: {
            'Content-Type': 'application/json',
            'x-user-id': userId,
          },
          body: json.encode({
            'title': newTitle,
            'lastModified': DateTime.now().toIso8601String(),
          }),
        );

        if (response.statusCode != 200) {
          throw Exception('Failed to update conversation title: ${response.statusCode}');
        }
      }

      _conversations.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      _filterConversations();
      notifyListeners();
      
      // 等待足夠長的時間讓 StreamingText 完成動畫
      await Future.delayed(const Duration(milliseconds: 500));
      
      debugPrint('Title update completed successfully (Trial Mode: $isTrialMode)');
    }
  } catch (e) {
    debugPrint('Error updating conversation title: $e');
    rethrow;
  } finally {
    _isTitleUpdating = false;
    notifyListeners();
  }
}

Future<void> saveMessage(Message message) async {
 if (_currentConversation == null) {
   debugPrint('No current conversation selected');
   throw Exception('No current conversation');
 }

 try {
   debugPrint('Saving message to conversation: ${_currentConversation!.id}');
   
   // 試用模式下的消息和圖片處理
   if (isTrialMode) {
     // 更新當前對話的時間戳和本地圖片
     List<Map<String, dynamic>> updatedImages = 
       List<Map<String, dynamic>>.from(_currentConversation!.localImages ?? []);
     
     // 如果消息包含新圖片，添加到對話的圖片列表中
     if (message.images != null && message.images!.isNotEmpty) {
       for (var image in message.images!) {
         if (!updatedImages.any((img) => img['url'] == image['url'])) {
           updatedImages.add(image);
         }
       }
     }

     _currentConversation = _currentConversation!.copyWith(
       lastModified: DateTime.now(),
       localImages: updatedImages,
     );
     
     // 更新對話列表中的對話
     final index = _conversations.indexWhere((c) => c.id == _currentConversation!.id);
     if (index != -1) {
       _conversations[index] = _currentConversation!;
       _conversations.sort((a, b) => b.lastModified.compareTo(a.lastModified));
     }
     
     _filterConversations();
     notifyListeners();
     debugPrint('Message saved in trial mode with ${updatedImages.length} images');
     return;
   }
   
   // 非試用模式的原有邏輯
   final messageData = message.toJson();
   if (message.searchResults != null) {
     messageData['searchResults'] = message.searchResults!.map((result) => result.toJson()).toList();
   }
   
   final response = await http.post(
     Uri.parse('$baseUrl/conversations/${_currentConversation!.id}/messages'),
     headers: {
       'Content-Type': 'application/json',
       'x-user-id': userId,
     },
     body: json.encode(messageData),
   );

   if (response.statusCode == 200) {
     debugPrint('Message saved successfully');
     debugPrint('Message content: ${messageData['content']}');
     if (messageData['searchResults'] != null) {
       debugPrint('Search results count: ${messageData['searchResults'].length}');
     }
     
     _currentConversation = _currentConversation!.copyWith(
       lastModified: DateTime.now(),
     );
     
     final index = _conversations.indexWhere((c) => c.id == _currentConversation!.id);
     if (index != -1) {
       _conversations[index] = _currentConversation!;
       _conversations.sort((a, b) => b.lastModified.compareTo(a.lastModified));
     }
     
     _filterConversations();
     notifyListeners();

     _channel?.sink.add(json.encode({
       'type': 'message_created',
       'conversationId': _currentConversation!.id,
       'message': messageData
     }));

     await loadConversations();
     
     debugPrint('WebSocket notification sent and conversations reloaded');

   } else {
     final error = 'Failed to save message: ${response.statusCode}\nResponse: ${response.body}';
     debugPrint(error);
     throw Exception(error);
   }
 } catch (e) {
   debugPrint('Error saving message: $e');
   rethrow;
 }
}
  Future<void> setCurrentConversation(Conversation conversation) async {
    debugPrint('Setting current conversation: ${conversation.id} with title: ${conversation.title}');
    _currentConversation = conversation.copyWith(); 
    notifyListeners();
    
    if (isTrialMode) {
      // 如果是試用模式，獲取本地存儲的消息
      final localMessages = _localMessages[conversation.id];
      if (localMessages != null) {
        debugPrint('Found ${localMessages.length} local messages for conversation: ${conversation.id}');
      }
      return;
    }
  
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/conversations/${conversation.id}/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': userId,
      },
    );

    if (response.statusCode == 200) {
      debugPrint('Messages loaded for conversation: ${conversation.id}');
      final data = json.decode(response.body);
      
      if (data is List) {
        for (var messageData in data) {
          if (messageData['searchResults'] != null) {
            debugPrint('Found message with search results: ${messageData['searchResults'].length} results');
          }
        }
      }
    } else {
      debugPrint('Failed to load messages: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Error loading messages: $e');
  }
}



Future<void> deleteConversation(String id) async {
  try {
    debugPrint('Deleting conversation: $id');
    
    // 試用模式只刪除本地數據
    if (isTrialMode) {
      _conversations.removeWhere((conv) => conv.id == id);
      if (_currentConversation?.id == id) {
        _currentConversation = null;
      }
      _filterConversations();
      notifyListeners();
      return;
    }

    final response = await http.delete(
      Uri.parse('$baseUrl/conversations/$id'),
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': userId,
      },
    );

    if (response.statusCode == 200) {
      _conversations.removeWhere((conv) => conv.id == id);
      if (_currentConversation?.id == id) {
        _currentConversation = null;
      }
      _filterConversations();
      notifyListeners();
    } else {
      throw Exception('Failed to delete conversation: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('Error deleting conversation: $e');
    rethrow;
  }
}
}