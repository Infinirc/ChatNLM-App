// lib/services/search_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/env.dart';

class SearchService {
  static const String baseUrl = 'https://search.infinirc.com';

  Future<Map<String, dynamic>> search(String query) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final response = await http.get(
        Uri.parse('$baseUrl/search?q=$encodedQuery&format=json'),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      throw Exception('搜尋失敗: ${response.statusCode}');
    } catch (e) {
      rethrow;
    }
  }
}