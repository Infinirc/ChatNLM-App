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
    if (messageId.isEmpty) return false;
    if (messageId.length == 24) return true;
    if (messageId.startsWith('trial_')) return true;
    if (messageId.startsWith('msg_')) {
      debugPrint('臨時消息ID，需要等待保存到伺服器: $messageId');
      return false;
    }
    return false;
  }

  String? getRating(String messageId, String userId, int version) {
    if (userId.isEmpty || messageId.isEmpty) return null;
    
    final ratingKey = '${userId}_$version';
    final rating = _ratingCache[messageId]?[ratingKey];
    debugPrint('獲取評分 - 消息ID: $messageId, 用戶ID: $userId, 版本: $version, 評分: $rating');
    return rating;
  }

  Map<String, String>? getAllRatings(String messageId) {
    return _ratingCache[messageId];
  }

  void updateRatingCache(String messageId, Map<String, dynamic> userRating) {
    debugPrint('更新評分緩存 - 消息ID: $messageId');
    debugPrint('原始評分數據: $userRating');

    final newRatings = Map<String, String>.from(
      userRating.map((key, value) => MapEntry(key, value.toString()))
    );
    
    if (_ratingCache.containsKey(messageId)) {
      // 合併現有評分，而不是完全替換
      _ratingCache[messageId]!.addAll(newRatings);
    } else {
      _ratingCache[messageId] = newRatings;
    }
    
    debugPrint('更新後的評分緩存: ${_ratingCache[messageId]}');
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
    debugPrint('處理消息評分:');
    debugPrint('- 消息ID: $messageId');
    debugPrint('- 對話ID: $conversationId');
    debugPrint('- 版本: $version');
    debugPrint('- 當前評分: $currentRating');
    debugPrint('- 新評分: $rating');
    
    try {
      // 更新本地緩存
      Map<String, String> updatedRatings;
      if (currentRating != null) {
        updatedRatings = Map<String, String>.from(currentRating);
      } else {
        updatedRatings = {};
      }

      // 如果新評分與當前評分相同，則移除評分（切換功能）
      if (updatedRatings[ratingKey] == rating) {
        updatedRatings.remove(ratingKey);
        debugPrint('移除相同評分: $ratingKey');
      } else {
        updatedRatings[ratingKey] = rating;
        debugPrint('添加新評分: $ratingKey = $rating');
      }

      _ratingCache[messageId] = updatedRatings;
      notifyListeners();
      debugPrint('緩存更新完成: ${_ratingCache[messageId]}');

      if (!isTrialMode) {
        debugPrint('發送評分到服務器...');
        final response = await http.post(
          Uri.parse('$baseUrl/conversations/$conversationId/messages/$messageId/rate'),
          headers: {
            'Content-Type': 'application/json',
            'x-user-id': userId,
          },
          body: json.encode({
            'rating': rating,
            'version': version,
            'currentRating': updatedRatings,
          }),
        );

        if (response.statusCode != 200) {
          debugPrint('服務器響應錯誤: ${response.statusCode}');
          // 恢復原始評分
          if (currentRating != null) {
            _ratingCache[messageId] = Map<String, String>.from(currentRating);
          } else {
            _ratingCache.remove(messageId);
          }
          notifyListeners();
          throw Exception('評分更新失敗');
        }
        debugPrint('服務器更新成功');
      }

    } catch (e, stack) {
      debugPrint('評分過程發生錯誤: $e');
      debugPrint('錯誤堆疊: $stack');
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