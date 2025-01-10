// lib/models/message.dart
import 'search_result.dart';

class Message {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final List<Map<String, String>>? images;
  final String role;
  final bool isComplete;
  final String id;
  final String? llmModel;
  final List<SearchResult>? searchResults;
  final List<String>? contentVersions;
  final int currentVersion;
  final Map<String, dynamic>? userRating;
    final bool isGeneratingImage;  // 新增
  final String? imagePrompt;     // 新增

  Message({
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.images,
    required this.role,
    this.isComplete = true,
    String? id,
    this.llmModel,
    this.searchResults,
    this.contentVersions,
    this.currentVersion = 0,
    this.userRating,
    this.isGeneratingImage = false,  // 新增
    this.imagePrompt,  
  }) : id = _generateId(id);

  // 生成合适的ID
  static String _generateId(String? id) {
    if (id != null) {
      if (id.length == 24) {
        return id;  // 如果是有效的MongoDB ID就直接使用
      }
      // 试用模式使用带前缀的时间戳
      if (id.startsWith('trial_')) {
        return id;
      }
    }
    // 其他情况使用带前缀的时间戳
    return 'msg_${DateTime.now().millisecondsSinceEpoch}';
  }

  int get totalVersions => contentVersions?.length ?? 1;

  factory Message.fromJson(Map<String, dynamic> json) {
    var imagesList = json['images'] as List?;
    List<Map<String, String>>? processedImages;
   
    if (imagesList != null) {
      processedImages = imagesList.map((img) {
        return Map<String, String>.from(img);
      }).toList();
    }

    List<SearchResult>? searchResults;
    if (json['searchResults'] != null) {
      searchResults = (json['searchResults'] as List)
          .map((result) => SearchResult.fromJson(result))
          .toList();
    }

    List<String>? contentVersions;
    if (json['contentVersions'] != null && json['contentVersions'] is List) {
      contentVersions = List<String>.from(json['contentVersions']);
    } else if (json['content'] != null) {
      contentVersions = [json['content']];
    }

    // 改进评分数据处理
    Map<String, dynamic>? userRating;
    if (json['userRating'] != null) {
      if (json['userRating'] is Map) {
        userRating = Map<String, dynamic>.from(json['userRating']);
      } else if (json['userRating'] is String) {
        // 处理旧格式的评分
        final version = json['currentVersion']?.toString() ?? '0';
        userRating = {
          version: json['userRating']
        };
      }
    }

    return Message(
      content: json['content'],
      isUser: json['role'] == 'user',
      timestamp: DateTime.parse(json['timestamp']),
      role: json['role'],
      llmModel: json['llmModel'],  // 添加這行
      isComplete: json['isComplete'] ?? true,
      id: json['_id'] ?? json['id'],
      images: processedImages,
      searchResults: searchResults,
      contentVersions: contentVersions,
      currentVersion: json['currentVersion'] ?? 0,
      userRating: userRating,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'role': role,
      'llmModel': llmModel,
      'timestamp': timestamp.toIso8601String(),
      'isComplete': isComplete,
      'images': images,
      'searchResults': searchResults?.map((result) => result.toJson()).toList(),
      'contentVersions': contentVersions,
      'currentVersion': currentVersion,
      'userRating': userRating,
      '_id': id,  // 使用 _id 以匹配服务器格式
    };
  }

  Message copyWith({
    String? content,
    bool? isUser,
    DateTime? timestamp,
    List<Map<String, String>>? images,
    String? role,
    String? llmModel,
    bool? isComplete,
    List<SearchResult>? searchResults,
    List<String>? contentVersions,
    int? currentVersion,
    Map<String, dynamic>? userRating,
  }) {
    return Message(
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      images: images ?? this.images,
      role: role ?? this.role,
      llmModel: llmModel ?? this.llmModel,
      isComplete: isComplete ?? this.isComplete,
      id: id,  // 保持原有ID
      searchResults: searchResults ?? this.searchResults,
      contentVersions: contentVersions ?? this.contentVersions,
      currentVersion: currentVersion ?? this.currentVersion,
      userRating: userRating ?? this.userRating,
    );
  }

  // 获取特定用户和版本的评分
  String? getUserRating(String userId, int version) {
    if (userRating == null) return null;
    final ratingKey = '${userId}_$version';
    return userRating![ratingKey]?.toString();
  }

  // 判断是否是有效的MongoDB ID
  bool get isValidMongoId => id.length == 24 && !id.startsWith('trial_');
}