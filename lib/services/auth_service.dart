//lib/services/auth_services.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;
import '../config/env.dart';

import 'package:http/http.dart' as http;

class AuthService {
  final _log = Logger('AuthService');
  static const String callbackUrlScheme = 'chatnlm';
  static const String _tokenKey = 'token';
  static const String _userIdKey = 'userId';

  String get baseUrl => _getBaseUrl();

  String _getBaseUrl() {
    if (kIsWeb) {
      return Env.authApiUrl;
    }
    return Platform.isAndroid
        ? 'http://10.0.2.2:8001'
        : Env.authApiUrl;
  }

  Future<String?> login() async {
    return _authenticate('login-page');
  }

  Future<String?> register() async {
    return _authenticate('register-page');
  }

  Future<String?> _authenticate(String page) async {
    try {
      if (kIsWeb) {
        return _webAuthenticate(page);
      } else {
        return _nativeAuthenticate(page);
      }
    } catch (e) {
      _log.warning('Authentication error', e);
      return null;
    }
  }

Future<String?> _webAuthenticate(String page) async {
  try {
    final callbackUrl = Env.webCallbackUrl;
    debugPrint('準備存儲回調 URL: $callbackUrl');
    
    // 首先，我們需要重定向到登入頁面
    final loginPageUrl = Uri.parse('${Env.authApiUrl}/auth/$page').replace(
      queryParameters: {
        'redirectUrl': callbackUrl,
      },
    );
    
    debugPrint('準備重定向到登入頁面，URL: $loginPageUrl');

    if (await canLaunchUrl(loginPageUrl)) {
      await launchUrl(
        loginPageUrl,
        webOnlyWindowName: '_self',
        mode: LaunchMode.platformDefault,
      );
      
      return await _waitForToken();
    }
  } catch (e) {
    debugPrint('Web 認證錯誤: $e');
  }
  return null;
}
Future<void> _storeRedirectUrl(String redirectUrl) async {
  try {
    await http.post(
      Uri.parse('${Env.authApiUrl}/auth/store-redirect'),
      body: json.encode({'redirectUrl': redirectUrl}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    debugPrint('儲存重定向 URL 失敗: $e');
  }
}
Future<String?> _waitForToken() async {
  if (kIsWeb) {
    final completer = Completer<String?>();
    var eventListener;
    
    // 創建事件監聽器
    eventListener = (html.Event event) {
      final storageEvent = event as html.StorageEvent;
      if (storageEvent.key == _tokenKey && storageEvent.newValue != null) {
        debugPrint('收到 token: ${storageEvent.newValue}');
        html.window.removeEventListener('storage', eventListener);
        completer.complete(storageEvent.newValue);
      }
    };
    
    // 添加監聽器
    html.window.addEventListener('storage', eventListener);
    
    // 檢查當前 URL 是否包含 token
    final uri = Uri.parse(html.window.location.href);
    final tokenFromUrl = uri.queryParameters['token'];
    if (tokenFromUrl != null) {
      debugPrint('從 URL 獲取 token');
      return tokenFromUrl;
    }
    
    // 檢查本地存儲
    final existingToken = html.window.localStorage[_tokenKey];
    if (existingToken != null) {
      debugPrint('從 localStorage 獲取現有 token');
      return existingToken;
    }

    // 設置超時
    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        debugPrint('認證超時');
        html.window.removeEventListener('storage', eventListener);
        return null;
      },
    );
  }
  return null;
}

  Future<String?> _nativeAuthenticate(String page) async {
    try {
      const callbackUrl = '$callbackUrlScheme://callback';
      final authUrl = '${Env.authApiUrl}/auth/$page?redirectUrl=$callbackUrl';
      debugPrint('Starting native authentication with URL: $authUrl');
      
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: callbackUrlScheme,
        options: const FlutterWebAuth2Options(
          preferEphemeral: false,
        ),
      );
      
      debugPrint('Received auth result: $result');
      return _handleAuthResult(result);
    } catch (e) {
      _log.warning('Native authentication error', e);
      return null;
    }
  }

  Future<String?> _handleAuthResult(String result) async {
    try {
      debugPrint('Handling auth result: $result');
      final uri = Uri.parse(result);
      final token = uri.queryParameters['token'];
      final status = uri.queryParameters['status'];
      final message = uri.queryParameters['message'];

      if (status == 'success' && token != null) {
        debugPrint('Auth successful, saving token');
        await _saveAuthData(token);
        return token;
      } else if (message != null) {
        _log.warning('Auth error: $message');
        throw Exception(message);
      }
      return null;
    } catch (e) {
      _log.warning('Error handling auth result: $e');
      return null;
    }
  }

  Future<void> _saveAuthData(String token) async {
    try {
      debugPrint('Saving auth data');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      
      final userId = _extractUserIdFromToken(token);
      debugPrint('Extracted userId: $userId');
      
      if (userId != null) {
        await prefs.setString(_userIdKey, userId);
        debugPrint('Saved userId to preferences');
      }

      if (kIsWeb) {
        html.window.localStorage[_tokenKey] = token;
        debugPrint('Saved token to localStorage');
      }
    } catch (e) {
      _log.warning('Error saving auth data: $e');
      rethrow;
    }
  }

  String? _extractUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = json.decode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))
        );
        final userId = payload['userId'] as String?;
        debugPrint('Extracted payload userId: $userId');
        return userId;
      }
    } catch (e) {
      _log.warning('Error extracting userId from token: $e');
    }
    return null;
  }

  Future<String?> getToken() async {
    try {
      if (kIsWeb) {
        final webToken = html.window.localStorage[_tokenKey];
        if (webToken != null) {
          return webToken;
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      debugPrint('Retrieved token from preferences: ${token != null ? 'found' : 'not found'}');
      return token;
    } catch (e) {
      _log.warning('Error getting token: $e');
      return null;
    }
  }

  Future<String?> getUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString(_userIdKey);
      debugPrint('Retrieved userId from preferences: $userId');
      
      if (userId == null) {
        final token = await getToken();
        if (token != null) {
          userId = _extractUserIdFromToken(token);
          if (userId != null) {
            await prefs.setString(_userIdKey, userId);
            debugPrint('Saved extracted userId to preferences: $userId');
          }
        }
      }
      
      return userId;
    } catch (e) {
      _log.warning('Error getting userId: $e');
      return null;
    }
  }

  Future<void> logout() async {
    try {
      debugPrint('Logging out...');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userIdKey);
      
      if (kIsWeb) {
        html.window.localStorage.remove(_tokenKey);
        debugPrint('Removed token from localStorage');
      }
      
      debugPrint('Logout successful');
    } catch (e) {
      _log.warning('Error during logout: $e');
      rethrow;
    }
  }
}