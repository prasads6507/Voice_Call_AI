import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _secureStorage = FlutterSecureStorage();
  
  // Keys
  static const String _sipUsername = 'sip_username';
  static const String _sipPassword = 'sip_password';
  static const String _sipDomain = 'sip_domain';
  static const String _gvNumber = 'gv_number';
  static const String _resumeText = 'resume_text';
  static const String _onboardingComplete = 'onboarding_complete';
  static const String _geminiApiKey = 'gemini_api_key';

  // SIP Credentials (secure)
  static Future<void> saveSipCredentials({
    required String username,
    required String password,
    required String domain,
  }) async {
    await _secureStorage.write(key: _sipUsername, value: username);
    await _secureStorage.write(key: _sipPassword, value: password);
    await _secureStorage.write(key: _sipDomain, value: domain);
  }

  static Future<Map<String, String>> getSipCredentials() async {
    return {
      'username': await _secureStorage.read(key: _sipUsername) ?? '',
      'password': await _secureStorage.read(key: _sipPassword) ?? '',
      'domain': await _secureStorage.read(key: _sipDomain) ?? 'sip2sip.info',
    };
  }

  static Future<bool> hasSipCredentials() async {
    final username = await _secureStorage.read(key: _sipUsername);
    return username != null && username.isNotEmpty;
  }

  // Gemini API Key (secure)
  static Future<void> saveGeminiApiKey(String key) async {
    await _secureStorage.write(key: _geminiApiKey, value: key);
  }

  static Future<String> getGeminiApiKey() async {
    return await _secureStorage.read(key: _geminiApiKey) ?? '';
  }

  static Future<bool> hasGeminiApiKey() async {
    final key = await _secureStorage.read(key: _geminiApiKey);
    return key != null && key.isNotEmpty;
  }

  // Google Voice Number
  static Future<void> saveGvNumber(String number) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gvNumber, number);
  }

  static Future<String> getGvNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_gvNumber) ?? '';
  }

  // Resume
  static Future<void> saveResume(String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_resumeText, text);
  }

  static Future<String> getResume() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_resumeText) ?? '';
  }

  // Onboarding
  static Future<void> setOnboardingComplete(bool complete) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingComplete, complete);
  }

  static Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingComplete) ?? false;
  }

  // Clear all data
  static Future<void> clearAll() async {
    await _secureStorage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
