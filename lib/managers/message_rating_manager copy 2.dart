//lib/managers/message_rating_manager.dart
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/message.dart';

class MessageRatingManager extends ChangeNotifier {
  final String baseUrl;
  final bool isTrialMode;
  final Map<String, Map<String, String>> _ratingCache = {};

  MessageRatingManager({
    required this.baseUrl,
    this.isTrialMode = false,
  }) {
    debugPrint('初始化 MessageRatingManager - 試用模式: $isTrialMode');
  }

  bool isValidMessageId(String messageId) {
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
    return _ratingCache[messageId]?[ratingKey];
  }

  void updateRatingCache(String messageId, Map<String, dynamic> userRating) {
    _ratingCache[messageId] = Map<String, String>.from(
      userRating.map((key, value) => MapEntry(key, value.toString()))
    );
    debugPrint('更新緩存評分: $messageId -> ${_ratingCache[messageId]}');
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

    if (!isValidMessageId(messageId)) {
      debugPrint('等待消息保存後再評分: $messageId');
      await Future.delayed(const Duration(milliseconds: 500));
      return;
    }

    final ratingKey = '${userId}_$version';
    
    try {
      debugPrint('處理消息評分 - 消息ID: $messageId, 對話ID: $conversationId, 版本: $version');
      
      // 先更新緩存，提供即時反饋
      if (_ratingCache[messageId]?[ratingKey] == rating) {
        _ratingCache[messageId]?.remove(ratingKey);
        if (_ratingCache[messageId]?.isEmpty == true) {
          _ratingCache.remove(messageId);
        }
      } else {
        _ratingCache[messageId] = {
          ...?currentRating,
          ratingKey: rating
        };
      }
      notifyListeners();

      if (!isTrialMode) {
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
            'currentRating': _ratingCache[messageId],
          }),
        );

        if (response.statusCode != 200) {
          // 恢復原始評分狀態
          if (currentRating != null) {
            _ratingCache[messageId] = Map<String, String>.from(currentRating);
          } else {
            _ratingCache.remove(messageId);
          }
          notifyListeners();
          throw Exception('評分更新失敗');
        }
      }

    } catch (e, stack) {
      debugPrint('評分過程發生錯誤: $e');
      debugPrint('錯誤堆疊: $stack');
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
    _ratingCache.clear();
    notifyListeners();
  }

  void printCache() {
    debugPrint('當前評分緩存狀態:');
    _ratingCache.forEach((messageId, ratings) {
      debugPrint('  消息 $messageId: $ratings');
    });
  }
}