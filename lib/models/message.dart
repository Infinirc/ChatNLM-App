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
final List<SearchResult>? searchResults;
final List<String>? contentVersions;
final int currentVersion;
final Map<String, dynamic>? userRating;  // 改為 Map 類型

Message({
  required this.content,
  required this.isUser,
  required this.timestamp,
  this.images,
  required this.role,
  this.isComplete = true,
  String? id,
  this.searchResults,
  this.contentVersions,
  this.currentVersion = 0,
  this.userRating,
}) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

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

   // 修改評分數據的處理邏輯
   Map<String, dynamic>? userRating;
   if (json['userRating'] != null) {
     userRating = Map<String, dynamic>.from(json['userRating'] is Map 
         ? json['userRating'] 
         : {});
   }

   return Message(
     content: json['content'],
     isUser: json['role'] == 'user',
     timestamp: DateTime.parse(json['timestamp']),
     role: json['role'],
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
    'timestamp': timestamp.toIso8601String(),
    'isComplete': isComplete,
    'images': images,
    'searchResults': searchResults?.map((result) => result.toJson()).toList(),
    'contentVersions': contentVersions,
    'currentVersion': currentVersion,
    'userRating': userRating,
    'id': id,
  };
}

Message copyWith({
 String? content,
 bool? isUser,
 DateTime? timestamp,
 List<Map<String, String>>? images,
 String? role,
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
   isComplete: isComplete ?? this.isComplete,
   id: id,
   searchResults: searchResults ?? this.searchResults,
   contentVersions: contentVersions ?? this.contentVersions,
   currentVersion: currentVersion ?? this.currentVersion,
   userRating: userRating, // 直接使用傳入的值
 );
}

Message createNewVersion(String newContent) {
  final List<String> newVersions = contentVersions?.toList() ?? [content];
  newVersions.add(newContent);
  
  return copyWith(
    content: newContent,
    contentVersions: newVersions,
    currentVersion: newVersions.length - 1,
  );
}

Message switchToVersion(int version) {
  if (contentVersions == null || version < 0 || version >= contentVersions!.length) {
    return this;
  }
  
  return copyWith(
    content: contentVersions![version],
    currentVersion: version,
  );
}

// 新增：獲取當前版本的評分
  String? getCurrentRating(String userId) {
    if (userRating == null) return null;
    final ratingKey = '${userId}_$currentVersion';
    return userRating![ratingKey];
  }

// 新增：設置當前版本的評分
Map<String, dynamic> setCurrentRating(String? rating) {
  final newRating = Map<String, dynamic>.from(userRating ?? {});
  if (rating == null) {
    newRating.remove(currentVersion.toString());
  } else {
    newRating[currentVersion.toString()] = rating;
  }
  return newRating;
}
}