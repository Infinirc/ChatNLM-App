// lib/utils/image_utils.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ImageUtils {
  static Future<String> imageToBase64(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(bytes);
      return 'data:image/png;base64,$base64Image';
    } catch (e) {
      debugPrint('Error converting image to base64: $e');
      rethrow;
    }
  }
}