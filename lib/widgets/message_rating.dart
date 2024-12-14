// lib/widgets/message_rating.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/message_rating_manager.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';

class MessageRating extends StatelessWidget {
  final Message message;
  final String conversationId;

  const MessageRating({
    super.key,
    required this.message,
    required this.conversationId,
  });

  Map<String, String>? _convertRating(Map<String, dynamic>? rating) {
    if (rating == null) return null;
    
    try {
      // 轉換並保留所有評分數據
      final convertedRating = rating.map(
        (key, value) => MapEntry(key, value.toString())
      );
      debugPrint('轉換評分數據: $convertedRating');
      return convertedRating;
    } catch (e) {
      debugPrint('評分數據轉換錯誤: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Consumer2<AuthProvider, MessageRatingManager>(
      builder: (context, authProvider, ratingManager, _) {
        final userId = authProvider.userId ?? '';
        
        // 從消息和緩存中獲取評分數據
        String? currentRating;
        Map<String, String>? allRatings;
        
        if (message.id.isNotEmpty) {
          // 優先使用緩存中的評分
          currentRating = ratingManager.getRating(
            message.id,
            userId,
            message.currentVersion,
          );
          
          // 獲取所有評分數據
          allRatings = message.userRating != null 
              ? _convertRating(message.userRating)
              : ratingManager.getAllRatings(message.id);
              
          debugPrint('構建評分組件:');
          debugPrint('- 消息ID: ${message.id}');
          debugPrint('- 版本: ${message.currentVersion}');
          debugPrint('- 當前評分: $currentRating');
          debugPrint('- 所有評分: $allRatings');
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                currentRating == 'like'
                    ? Icons.thumb_up
                    : Icons.thumb_up_outlined,
                size: 16,
                color: currentRating == 'like'
                    ? Colors.blue
                    : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
              ),
              onPressed: message.id.isEmpty ? null : () {
                ratingManager.rateMessage(
                  messageId: message.id,
                  conversationId: conversationId,
                  userId: userId,
                  rating: 'like',
                  version: message.currentVersion,
                  currentRating: allRatings,
                );
              },
              splashRadius: 24,
              tooltip: '讚',
            ),
            IconButton(
              icon: Icon(
                currentRating == 'dislike'
                    ? Icons.thumb_down
                    : Icons.thumb_down_outlined,
                size: 16,
                color: currentRating == 'dislike'
                    ? Colors.red
                    : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
              ),
              onPressed: message.id.isEmpty ? null : () {
                ratingManager.rateMessage(
                  messageId: message.id,
                  conversationId: conversationId,
                  userId: userId,
                  rating: 'dislike',
                  version: message.currentVersion,
                  currentRating: allRatings,
                );
              },
              splashRadius: 24,
              tooltip: '倒讚',
            ),
          ],
        );
      },
    );
  }
}