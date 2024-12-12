import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/search_result.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:html' if (dart.library.html) 'dart:html' as html;
import '../config/env.dart';
import 'package:http/http.dart' as http;

class SearchResults extends StatelessWidget {
  final List<SearchResult> results;
  final VoidCallback onClose;

  const SearchResults({
    super.key,
    required this.results,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxHeight: 400,
        maxWidth: 600,
      ),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text(
                  '引用',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                return ListTile(
                  leading: _buildResultIcon(result),
                  title: Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    result.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    // 處理點擊事件
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultIcon(SearchResult result) {
    if (_isSpecialEngine(result.engine)) {
      return _buildCustomIcon(result.engine);
    }

    if (result.favicon == null || result.favicon!.isEmpty) {
      debugPrint('No favicon URL available');
      return _buildFallbackIcon();
    }

    debugPrint('Attempting to load favicon: ${result.favicon}');

    return Container(
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Image.network(
        result.favicon!,
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame == null) {
            debugPrint('Still loading favicon...');
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            );
          }
          debugPrint('Favicon loaded successfully');
          return child;
        },
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error loading favicon: $error');
          debugPrint('Stack trace: $stackTrace');
          return _buildFallbackIcon();
        },
        headers: kIsWeb ? {
          'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
          'Accept-Encoding': 'gzip, deflate, br',
          'Origin': Uri.base.origin,
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        } : null,
      ),
    );
  }

  Future<bool> _checkImageAvailability(String url) async {
    if (!kIsWeb) return true;
    
    try {
      final response = await http.head(Uri.parse(url));
      debugPrint('Image check response for $url: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error checking image availability: $e');
      return false;
    }
  }

  bool _isSpecialEngine(String engine) {
    return ['langchain', 'nvidia', 'proxmox'].contains(engine.toLowerCase());
  }

  Widget _buildCustomIcon(String engine) {
    IconData iconData;
    Color color;
    
    switch (engine.toLowerCase()) {
      case 'langchain':
        iconData = Icons.auto_awesome;
        color = Colors.purple;
        break;
      case 'nvidia':
        iconData = Icons.memory;
        color = Colors.green;
        break;
      case 'proxmox':
        iconData = Icons.storage;
        color = Colors.orange;
        break;
      default:
        return _buildFallbackIcon();
    }

    return Container(
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        iconData,
        color: color,
        size: 20,
      ),
    );
  }

  Widget _buildFallbackIcon() {
    return Container(
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.public,
        color: Colors.blue,
        size: 20,
      ),
    );
  }
}