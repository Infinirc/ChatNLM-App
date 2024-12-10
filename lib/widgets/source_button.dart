// lib/widgets/source_button.dart
import 'package:flutter/material.dart';

class SourceButton extends StatelessWidget {
  final List<String> sources;
  final VoidCallback onTap;

  const SourceButton({
    super.key,
    required this.sources,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[700]!),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '資料來源',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            ...sources.take(3).map((source) => _buildSourceIcon(source)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceIcon(String source) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 20,
          height: 20,
          color: _getSourceColor(source),
          child: Center(
            child: Icon(
              _getSourceIcon(source),
              size: 14,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  IconData _getSourceIcon(String source) {
    switch (source.toLowerCase()) {
      case 'nvidia':
        return Icons.memory;
      case 'proxmox':
        return Icons.storage;
      default:
        return Icons.public;
    }
  }

  Color _getSourceColor(String source) {
    switch (source.toLowerCase()) {
      case 'nvidia':
        return Colors.green;
      case 'proxmox':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }
}