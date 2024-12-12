// lib/models/search_result.dart
import 'package:flutter/foundation.dart';
import '../config/env.dart';

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
  if (json['url'] == null || 
      json['title'] == null || 
      json['content'] == null ||
      json['content'].toString().isEmpty ||
      json['engine'] == null) {
    throw FormatException('Invalid search result data: Missing required fields');
  }

  final uri = Uri.parse(json['url']);
  String? faviconUrl;
  
  if (!['langchain', 'nvidia', 'proxmox'].contains(json['engine'].toString().toLowerCase())) {
    final baseUrl = '${Env.searchApiUrl}/search/favicon';
    final params = {
      'domain': uri.host,
      if (kIsWeb) ...{
        'platform': 'web',
        't': DateTime.now().millisecondsSinceEpoch.toString(),
        'origin': Uri.base.origin,
      },
    };
    
    final faviconUri = Uri.parse(baseUrl).replace(queryParameters: params);
    faviconUrl = faviconUri.toString();
    debugPrint('Generated favicon URL: $faviconUrl');
  }

  return SearchResult(
    url: json['url'] as String,
    title: json['title'] as String,
    content: json['content'] as String,
    thumbnail: json['thumbnail'] as String?,
    engine: json['engine'] as String,
    engines: List<String>.from(json['engines'] ?? []),
    favicon: faviconUrl,
  );
}

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