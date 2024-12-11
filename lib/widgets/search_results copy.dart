// lib/widgets/search_results.dart
import 'package:flutter/material.dart';
import '../models/search_result.dart';

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
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標題列
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
          // 搜尋結果列表
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: results.length,
            itemBuilder: (context, index) {
              final result = results[index];
              return ListTile(
                leading: _buildSourceIcon(result.engine),
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
        ],
      ),
    );
  }

  Widget _buildSourceIcon(String engine) {
    IconData iconData;
    Color color;
    
    switch (engine.toLowerCase()) {
      case 'nvidia':
        iconData = Icons.memory;
        color = Colors.green;
        break;
      case 'proxmox':
        iconData = Icons.storage;
        color = Colors.orange;
        break;
      default:
        iconData = Icons.public;
        color = Colors.blue;
    }

    return Container(
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
}