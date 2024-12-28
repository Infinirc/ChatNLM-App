//conversation.dart
class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime lastModified;
  final List<Map<String, dynamic>>? localImages;
  final String? llmModel;

  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.lastModified,
    this.localImages,
    this.llmModel,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>>? images;
    if (json['localImages'] != null) {
      images = (json['localImages'] as List)
          .map((img) => Map<String, dynamic>.from(img))
          .toList();
    }

    return Conversation(
      id: json['_id'] ?? json['id'],
      title: json['title'],
      createdAt: DateTime.parse(json['createdAt']),
      lastModified: DateTime.parse(json['lastModified']),
      localImages: images,
      llmModel: json['llmModel']?.toString(),  // 從 JSON 讀取模型資訊
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      '_id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'lastModified': lastModified.toIso8601String(),
      'llmModel': llmModel, 
    };

    if (localImages != null && localImages!.isNotEmpty) {
      data['localImages'] = localImages;
    }

    return data;
  }

  Conversation copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? lastModified,
    List<Map<String, dynamic>>? localImages,
    String? llmModel, 
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
      localImages: localImages ?? this.localImages,
      llmModel: llmModel ?? this.llmModel,
    );
  }

  @override
  bool operator ==(Object other) =>
    identical(this, other) ||
    other is Conversation &&
    runtimeType == other.runtimeType &&
    id == other.id &&
    title == other.title &&
    createdAt == other.createdAt &&
    lastModified == other.lastModified &&
    _compareLocalImages(localImages, other.localImages);

  bool _compareLocalImages(
    List<Map<String, dynamic>>? list1,
    List<Map<String, dynamic>>? list2
  ) {
    if (list1 == null && list2 == null) return true;
    if (list1 == null || list2 == null) return false;
    if (list1.length != list2.length) return false;

    for (int i = 0; i < list1.length; i++) {
      final url1 = list1[i]['url'] as String?;
      final url2 = list2[i]['url'] as String?;
      if (url1 != url2) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    int imagesHash = 0;
    if (localImages != null) {
      for (var img in localImages!) {
        final url = img['url'] as String?;
        if (url != null) {
          imagesHash ^= url.hashCode;
        }
      }
    }
    
    return id.hashCode ^
           title.hashCode ^
           createdAt.hashCode ^
           lastModified.hashCode ^
           imagesHash;
  }

  @override
  String toString() =>
    'Conversation(id: $id, title: $title, createdAt: $createdAt, lastModified: $lastModified, localImagesCount: ${localImages?.length ?? 0})';
}