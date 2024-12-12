//lib/managers/message_rating_manager.dart
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/message.dart';

class MessageRatingManager extends ChangeNotifier {
  final String baseUrl;
  final bool isTrialMode;
  final Map<String, Map<String, Map<String, String>>> _ratingCache = {};

  MessageRatingManager({
    required this.baseUrl,
    this.isTrialMode = false,
  }) {
    debugPrint('初始化 MessageRatingManager - 試用模式: $isTrialMode');
  }

  bool _isValidMessageId(String messageId) {
    if (messageId.length == 24) {
      return true;
    }
    if (messageId.startsWith('trial_')) {
      return true;
    }
    if (messageId.startsWith('msg_')) {
      debugPrint('臨時消息ID，需要等待保存到伺服器: $messageId');
      return false;
    }
    return false;
  }

  String? getRating(String messageId, String userId, int version) {
    if (userId.isEmpty || messageId.isEmpty) {
      return null;
    }
    
    final ratingKey = '${userId}_$version';
    
    // 直接從 Message 的 userRating 中獲取評分狀態
    final userRating = _ratingCache[messageId]?['default']?[ratingKey];
    if (userRating != null) {
      return userRating;
    }

    return null;
  }

  // 更新緩存中的評分數據
  void updateRatingCache(String messageId, Map<String, dynamic> userRating) {
    _ratingCache[messageId] = {
      'default': Map<String, String>.from(
        userRating.map((key, value) => MapEntry(key, value.toString()))
      )
    };
    notifyListeners();
  }

Future<void> rateMessage({
  required String messageId,
  required String conversationId,
  required String userId,
  required String rating,
  required int version,
  required Map<String, String>? currentRating,
}) async {
  if (userId.isEmpty || conversationId.isEmpty || messageId.isEmpty) {
    debugPrint('無效的評分參數');
    return;
  }

  if (!_isValidMessageId(messageId)) {
    debugPrint('等待消息保存後再評分: $messageId');
    await Future.delayed(const Duration(milliseconds: 500));
    return;
  }

  final ratingKey = '${userId}_$version';
  
  try {
    debugPrint('處理消息評分 - 消息ID: $messageId, 對話ID: $conversationId, 版本: $version');
    debugPrint('當前評分數據: $currentRating');
    
    // 試用模式邏輯保持不變
    if (isTrialMode) {
      final shouldRemove = _ratingCache[messageId]?['default']?[ratingKey] == rating;
      if (shouldRemove) {
        _ratingCache[messageId]?['default']?.remove(ratingKey);
      } else {
        _ratingCache[messageId] = {
          'default': {ratingKey: rating}
        };
      }
      notifyListeners();
      return;
    }

    // 先更新本地緩存，提供即時反饋
    final shouldRemove = _ratingCache[messageId]?['default']?[ratingKey] == rating;
    if (shouldRemove) {
      _ratingCache[messageId]?['default']?.remove(ratingKey);
    } else {
      _ratingCache[messageId] = {
        'default': currentRating?.map((key, value) => 
          MapEntry(key, value.toString())) ?? {}
      };
      _ratingCache[messageId]!['default']![ratingKey] = rating;
    }
    notifyListeners();

    debugPrint('正在發送評分到伺服器...');
    final response = await http.post(
      Uri.parse('$baseUrl/conversations/$conversationId/messages/$messageId/rate'),
      headers: {
        'Content-Type': 'application/json',
        'x-user-id': userId,
      },
      body: json.encode({
        'rating': rating,
        'version': version,
        'currentRating': _ratingCache[messageId]?['default'],  // 發送完整的評分數據
      }),
    );

    if (response.statusCode == 200) {
      debugPrint('伺服器評分更新成功');
      final data = json.decode(response.body);
      
      if (data['userRating'] != null) {
        // 使用伺服器返回的數據更新緩存
        updateRatingCache(messageId, data['userRating']);
        debugPrint('評分緩存已更新: ${json.encode(_ratingCache[messageId])}');
      }
    } else {
      debugPrint('伺服器請求失敗: ${response.statusCode}, ${response.body}');
      // 恢復原始評分狀態
      if (currentRating != null) {
        _ratingCache[messageId] = {
          'default': Map<String, String>.from(currentRating)
        };
      } else {
        _ratingCache.remove(messageId);
      }
      notifyListeners();
      throw Exception('評分更新失敗');
    }
  } catch (e, stack) {
    debugPrint('評分過程發生錯誤: $e');
    debugPrint('錯誤堆疊: $stack');
    // 確保錯誤狀態也通知監聽器
    notifyListeners();
  }
}
  void updateMessageId(String oldId, String newId) {
    final ratings = _ratingCache[oldId];
    if (ratings != null) {
      _ratingCache[newId] = ratings;
      _ratingCache.remove(oldId);
      notifyListeners();
    }
  }

  void clearRatings() {
    debugPrint('清除所有評分緩存');
    _ratingCache.clear();
    notifyListeners();
  }
  
  void clearConversationRatings(String conversationId) {
    debugPrint('清除對話 $conversationId 的評分緩存');
    _ratingCache.clear(); // 清除所有緩存，因為我們現在按消息ID存儲
    notifyListeners();
  }

  void printCache() {
    debugPrint('當前評分緩存狀態:');
    _ratingCache.forEach((messageId, ratings) {
      debugPrint('  消息 $messageId: $ratings');
    });
  }
}