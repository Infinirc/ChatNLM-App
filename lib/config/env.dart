// lib/config/env.dart
class Env {
  // Base URLs (保持現有的不變)
  static const String authApiUrl = 'https://chatnlm-auth.api.infinirc.com';
  static const String conversationApiUrl = 'https://chatnlm-conversation.api.infinirc.com';
  static const String llmApiUrl = 'https://chatnlm.api.infinirc.com/v1';
  static const String voiceApiUrl = 'https://chatnlm-tts.api.infinirc.com';
  
  // Auth endpoints (保持現有的不變)
  static String get loginUrl => '$authApiUrl/auth/login-page';
  static String get registerUrl => '$authApiUrl/auth/register-page';
  static String get logoutUrl => '$authApiUrl/auth/logout';
  
  // Conversation endpoints (保持現有的不變)
  static String get conversationsUrl => '$conversationApiUrl/conversations';
  static String conversationUrl(String id) => '$conversationApiUrl/conversations/$id';
  static String conversationMessagesUrl(String id) => '$conversationApiUrl/conversations/$id/messages';
  
  // LLM endpoints
  static String get modelsUrl => '$llmApiUrl/models';
  static String get chatCompletionsUrl => '$llmApiUrl/chat/completions';
  // 新增 WebSocket endpoint
  static String get chatCompletionsWsUrl => 'ws://chatnlm.api.infinirc.com/v1/chat/completions';
  
  // Search endpoints (保持現有的不變)
  static const String searchApiUrl = 'https://search.infinirc.com';
  static String searchEndpoint(String query) => '$searchApiUrl/search?q=$query&format=json';
  
  // Voice endpoints (保持現有的不變)
  static String get processAudioUrl => '$voiceApiUrl/process-audio';
  static String get audioDevicesUrl => '$voiceApiUrl/api/audio-devices';
  static String get voiceInputUrl => '$voiceApiUrl/api/voice-input';
}