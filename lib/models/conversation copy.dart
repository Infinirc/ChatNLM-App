//conversation.dart
class Conversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime lastModified;

  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.lastModified,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['_id'] ?? json['id'],
      title: json['title'],
      createdAt: DateTime.parse(json['createdAt']),
      lastModified: DateTime.parse(json['lastModified']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'lastModified': lastModified.toIso8601String(),
    };
  }

  Conversation copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? lastModified,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
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
    lastModified == other.lastModified;

  @override
  int get hashCode =>
    id.hashCode ^
    title.hashCode ^
    createdAt.hashCode ^
    lastModified.hashCode;

  @override
  String toString() =>
    'Conversation(id: $id, title: $title, createdAt: $createdAt, lastModified: $lastModified)';
}