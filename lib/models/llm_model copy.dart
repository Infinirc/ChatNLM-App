// lib/models/llm_model.dart
import 'package:flutter/foundation.dart';

class LlmModel {
  final String id;
  final String object;
  final int created;
  final String ownedBy;
  final String root;
  final String? parent;
  final int maxModelLen;

  LlmModel({
    required this.id,
    required this.object,
    required this.created,
    required this.ownedBy,
    required this.root,
    required this.parent,
    required this.maxModelLen,
  });

  factory LlmModel.fromJson(Map<String, dynamic> json) {
    return LlmModel(
      id: json['id'] as String,
      object: json['object'] as String,
      created: json['created'] as int,
      ownedBy: json['owned_by'] as String,
      root: json['root'] as String,
      parent: json['parent'] as String?,
      maxModelLen: json['max_model_len'] as int,
    );
  }
}