//lib/service/api_service.dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService {
  final String baseUrl;
  
  ApiService(this.baseUrl);

  Future<List<String>> getAvailableModels() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/models'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['data'] as List)
            .map((model) => model['id'] as String)
            .toList();
      }
      throw Exception('Failed to load models');
    } catch (e) {
      rethrow;
    }
  }
}