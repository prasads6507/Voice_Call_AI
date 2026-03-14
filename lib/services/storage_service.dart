
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class StorageService {
  static const _secureStorage = FlutterSecureStorage();
  
  // Keys
  static const String _sipUsername = 'sip_username';
  static const String _sipPassword = 'sip_password';
  static const String _sipDomain = 'sip_domain';
  static const String _gvNumber = 'gv_number';
  static const String _resumeText = 'resume_text';
  static const String _onboardingComplete = 'onboarding_complete';
  static const String _whisperModelReady = 'whisper_model_ready';
  static const String _gemmaModelReady = 'gemma_model_ready';

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

  // Model Status
  static Future<void> setModelReady(String modelKey, bool ready) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(modelKey, ready);
  }

  static Future<bool> isWhisperReady() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_whisperModelReady) ?? false;
  }

  static Future<bool> isGemmaReady() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_gemmaModelReady) ?? false;
  }

  static Future<void> setWhisperReady(bool ready) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_whisperModelReady, ready);
  }

  static Future<void> setGemmaReady(bool ready) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gemmaModelReady, ready);
  }

  // Model file paths
  static Future<String> get modelsDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir.path;
  }

  static Future<String> get whisperModelPath async {
    final dir = await modelsDirectory;
    return '$dir/ggml-tiny.bin';
  }

  static Future<String> get gemmaModelPath async {
    final dir = await modelsDirectory;
    return '$dir/gemma-3-1b-it-q4_k_m.gguf';
  }

  static Future<bool> whisperModelExists() async {
    final path = await whisperModelPath;
    return File(path).existsSync();
  }

  static Future<bool> gemmaModelExists() async {
    final path = await gemmaModelPath;
    return File(path).existsSync();
  }

  // Clear all data
  static Future<void> clearAll() async {
    await _secureStorage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
