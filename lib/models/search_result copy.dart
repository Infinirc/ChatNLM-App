// lib/models/search_result.dart
class SearchResult {
  final String url;
  final String title;
  final String content;
  final String? thumbnail;
  final String engine;
  final List<String> engines;
  final String? favicon;

  SearchResult({
    required this.url,
    required this.title,
    required this.content,
    this.thumbnail,
    required this.engine,
    required this.engines,
    this.favicon,
  });

factory SearchResult.fromJson(Map<String, dynamic> json) {
  // 確保所有必要欄位都存在且有效
  if (json['url'] == null || 
      json['title'] == null || 
      json['content'] == null ||
      json['content'].toString().isEmpty ||
      json['engine'] == null) {
    throw FormatException('Invalid search result data: Missing required fields');
  }

  final uri = Uri.parse(json['url']);
  return SearchResult(
    url: json['url'] as String,
    title: json['title'] as String,
    content: json['content'] as String,
    thumbnail: json['thumbnail'] as String?,
    engine: json['engine'] as String,
    engines: List<String>.from(json['engines'] ?? []),
    favicon: json['favicon'] ?? 'https://www.google.com/s2/favicons?domain=${uri.host}',
  );
}

  // 添加 toJson 方法
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'title': title,
      'content': content,
      'thumbnail': thumbnail,
      'engine': engine,
      'engines': engines,
      'favicon': favicon,
    };
  }

  // 可選：添加 copyWith 方法以方便修改
  SearchResult copyWith({
    String? url,
    String? title,
    String? content,
    String? thumbnail,
    String? engine,
    List<String>? engines,
    String? favicon,
  }) {
    return SearchResult(
      url: url ?? this.url,
      title: title ?? this.title,
      content: content ?? this.content,
      thumbnail: thumbnail ?? this.thumbnail,
      engine: engine ?? this.engine,
      engines: engines ?? this.engines,
      favicon: favicon ?? this.favicon,
    );
  }

  // 可選：添加比較運算子
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          title == other.title &&
          content == other.content &&
          thumbnail == other.thumbnail &&
          engine == other.engine &&
          favicon == other.favicon;

  @override
  int get hashCode =>
      url.hashCode ^
      title.hashCode ^
      content.hashCode ^
      thumbnail.hashCode ^
      engine.hashCode ^
      favicon.hashCode;

  @override
  String toString() {
    return 'SearchResult(url: $url, title: $title, content: $content, thumbnail: $thumbnail, engine: $engine, engines: $engines, favicon: $favicon)';
  }
}