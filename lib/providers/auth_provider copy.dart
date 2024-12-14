//lib/providers/auth_provider.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  bool _isAuthenticated = false;
  bool _isTrialMode = false;
  String? _token;
  String? _userId;
  String? _userName;
  
  
  bool get isAuthenticated => _isAuthenticated;
  bool get isTrialMode => _isTrialMode;
  String? get token => _token;
  String? get userId => _userId;
  String? get userName => _userName;

  AuthProvider() {
    _loadState();
  }

  // 新增：加載保存的狀態
  Future<void> _loadState() async {
    try {
      debugPrint('Loading saved state...');
      final prefs = await SharedPreferences.getInstance();
      _isTrialMode = prefs.getBool('isTrialMode') ?? false;
      
      if (_isTrialMode) {
        debugPrint('Restoring trial mode');
        _isAuthenticated = false;
        _token = null;
        _userId = 'trial_user_${DateTime.now().millisecondsSinceEpoch}';
        _userName = 'Trial User';
        notifyListeners();
      } else {
        await _checkAuth();
      }
    } catch (e) {
      debugPrint('Error loading saved state: $e');
      await _checkAuth();
    }
  }

  // 修改：保存試用模式狀態
  Future<void> enterTrialMode() async {
    try {
      _isTrialMode = true;
      _isAuthenticated = false;
      _token = null;
      _userId = 'trial_user_${DateTime.now().millisecondsSinceEpoch}';
      _userName = 'Trial User';
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isTrialMode', true);
      
      debugPrint('Entered and saved trial mode - userId: $_userId');
      notifyListeners();
    } catch (e) {
      debugPrint('Error entering trial mode: $e');
    }
  }

  // 修改：清除試用模式狀態
  Future<void> exitTrialMode() async {
    try {
      _isTrialMode = false;
      _isAuthenticated = false;
      _token = null;
      _userId = null;
      _userName = null;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isTrialMode');
      
      debugPrint('Exited and cleared trial mode');
      notifyListeners();
    } catch (e) {
      debugPrint('Error exiting trial mode: $e');
    }
  }

  Map<String, dynamic>? _decodeToken(String token) {
    try {
      debugPrint('Decoding token: ${token.substring(0, 20)}...');
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = json.decode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))
        );
        return payload;
      }
    } catch (e) {
      debugPrint('Error decoding token: $e');
    }
    return null;
  }

  void _extractUserInfo(String token) {
    final payload = _decodeToken(token);
    if (payload != null) {
      _userId = payload['userId'] as String?;
      _userName = payload['name'] as String?;
      debugPrint('Extracted user info - userId: $_userId, name: $_userName');
    }
  }

  Future<void> _checkAuth() async {
    try {
      debugPrint('Checking authentication status...');
      if (_isTrialMode) {
        debugPrint('In trial mode, skipping auth check');
        return;
      }

      _token = await _authService.getToken();
      
      if (_token != null) {
        _extractUserInfo(_token!);
        _isAuthenticated = _userId != null;
        debugPrint('Auth check completed - token exists, '
            'userId: $_userId, name: $_userName, isAuthenticated: $_isAuthenticated');
      } else {
        _isAuthenticated = false;
        _userId = null;
        _userName = null;
        debugPrint('No token found, user is not authenticated');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error during auth check: $e');
      _handleAuthError();
    }
  }

  void _handleAuthError() {
    if (!_isTrialMode) {
      _isAuthenticated = false;
      _token = null;
      _userId = null;
      _userName = null;
    }
    notifyListeners();
  }

Future<bool> login() async {
  try {
    debugPrint('Attempting login...');
    final token = await _authService.login();
    
    if (token != null) {
      // 先清除試用模式的所有狀態
      if (_isTrialMode) {
        await exitTrialMode();
      }
      
      _token = token;
      _extractUserInfo(token);
      _isAuthenticated = _userId != null;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
      
      debugPrint('Login successful - userId: $_userId, name: $_userName');
      notifyListeners();
      
      // 確保狀態完全更新
      await Future.delayed(const Duration(milliseconds: 100));
      return true;
    }
    
    debugPrint('Login failed - no token received');
    return false;
  } catch (e) {
    debugPrint('Login error: $e');
    _handleAuthError();
    return false;
  }
}

Future<bool> register() async {
  try {
    await exitTrialMode();

    debugPrint('Attempting registration...');
    final token = await _authService.register();
    
    if (token != null) {
      // 保存 token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
      
      // 設置 token 和提取用戶信息
      _token = token;
      _extractUserInfo(token);  // 確保提取用戶信息
      _isAuthenticated = _userId != null;
      
      // 輸出日誌以便調試
      debugPrint('Registration successful - token saved');
      debugPrint('User info after registration - userId: $_userId, name: $_userName');
      
      notifyListeners();
      
      // 確保更新完成
      await Future.delayed(const Duration(milliseconds: 100));
      return true;
    }
    
    debugPrint('Registration failed - no token received');
    return false;
  } catch (e) {
    debugPrint('Registration error: $e');
    _handleAuthError();
    return false;
  }
}

  // 修改：試用模式下不退出試用
Future<void> logout() async {
  try {
    debugPrint('Logging out...');
    await _authService.logout();
    
    // 不論是否為試用模式，都需要清除狀態
    _isTrialMode = false;
    _isAuthenticated = false;
    _token = null;
    _userId = null;
    _userName = null;
    
    // 清除試用模式的 SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isTrialMode');
    
    debugPrint('Logout successful, cleared all states');
    notifyListeners();
  } catch (e) {
    debugPrint('Logout error: $e');
    _handleAuthError();
  }
}

Future<void> refreshAuthState() async {
  try {
    await _checkAuth();  // 檢查認證狀態
    notifyListeners();   // 通知所有監聽器
    await Future.delayed(const Duration(milliseconds: 50));  // 給予時間更新
  } catch (e) {
    debugPrint('Error refreshing auth state: $e');
  }
}

  bool isTokenValid() {
    if (_isTrialMode) return true;
    if (_token == null) return false;
    
    try {
      final payload = _decodeToken(_token!);
      if (payload != null && payload['exp'] != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(payload['exp'] * 1000);
        final isValid = expiry.isAfter(DateTime.now());
        debugPrint('Token validity check - expires: $expiry, isValid: $isValid');
        return isValid;
      }
    } catch (e) {
      debugPrint('Error checking token validity: $e');
    }
    return false;
  }

  String? getUserRole() {
    if (_isTrialMode) return 'trial';
    if (_token == null) return null;
    
    try {
      final payload = _decodeToken(_token!);
      return payload?['role'] as String?;
    } catch (e) {
      debugPrint('Error extracting user role: $e');
    }
    return null;
  }
}