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
  final List<ModelPermission> permission;

  LlmModel({
    required this.id,
    required this.object,
    required this.created,
    required this.ownedBy,
    required this.root,
    required this.parent,
    required this.maxModelLen,
    required this.permission,
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
      permission: (json['permission'] as List)
          .map((p) => ModelPermission.fromJson(p))
          .toList(),
    );
  }
}

class ModelPermission {
  final String id;
  final String object;
  final int created;
  final bool allowCreateEngine;
  final bool allowSampling;
  final bool allowLogprobs;
  final bool allowSearchIndices;
  final bool allowView;
  final bool allowFineTuning;
  final String organization;
  final String? group;
  final bool isBlocking;

  ModelPermission({
    required this.id,
    required this.object,
    required this.created,
    required this.allowCreateEngine,
    required this.allowSampling,
    required this.allowLogprobs,
    required this.allowSearchIndices,
    required this.allowView,
    required this.allowFineTuning,
    required this.organization,
    required this.group,
    required this.isBlocking,
  });

  factory ModelPermission.fromJson(Map<String, dynamic> json) {
    return ModelPermission(
      id: json['id'] as String,
      object: json['object'] as String,
      created: json['created'] as int,
      allowCreateEngine: json['allow_create_engine'] as bool,
      allowSampling: json['allow_sampling'] as bool,
      allowLogprobs: json['allow_logprobs'] as bool,
      allowSearchIndices: json['allow_search_indices'] as bool,
      allowView: json['allow_view'] as bool,
      allowFineTuning: json['allow_fine_tuning'] as bool,
      organization: json['organization'] as String,
      group: json['group'] as String?,
      isBlocking: json['is_blocking'] as bool,
    );
  }
}