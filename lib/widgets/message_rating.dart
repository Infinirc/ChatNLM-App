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
    return rating.map((key, value) => MapEntry(key, value.toString()));
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Consumer2<AuthProvider, MessageRatingManager>(
      builder: (context, authProvider, ratingManager, child) {  // 添加 child 参数
        final userId = authProvider.userId ?? '';
        final currentRating = ratingManager.getRating(
          message.id,
          userId,
          message.currentVersion,
        );

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
              onPressed: () => ratingManager.rateMessage(
                messageId: message.id,
                conversationId: conversationId,
                userId: userId,
                rating: 'like',
                version: message.currentVersion,
                currentRating: _convertRating(message.userRating),
              ),
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
              onPressed: () => ratingManager.rateMessage(
                messageId: message.id,
                conversationId: conversationId,
                userId: userId,
                rating: 'dislike',
                version: message.currentVersion,
                currentRating: _convertRating(message.userRating),
              ),
              splashRadius: 24,
              tooltip: '倒讚',
            ),
          ],
        );
      },
    );
  }
}