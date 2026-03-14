import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'storage_service.dart';

enum DownloadState {
  idle,
  downloading,
  paused,
  completed,
  error,
}

class ModelDownloadService extends ChangeNotifier {
  // Model URLs (Hugging Face hosted GGUF models)
  static const String whisperUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin';
  static const String gemmaUrl =
      'https://huggingface.co/lmstudio-community/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf';

  static const int whisperExpectedSize = 75 * 1024 * 1024; // ~75MB
  static const int gemmaExpectedSize = 800 * 1024 * 1024; // ~800MB

  final Dio _dio = Dio();
  CancelToken? _whisperCancelToken;
  CancelToken? _gemmaCancelToken;

  // Whisper download state
  DownloadState _whisperState = DownloadState.idle;
  double _whisperProgress = 0.0;
  String _whisperError = '';

  // Gemma download state
  DownloadState _gemmaState = DownloadState.idle;
  double _gemmaProgress = 0.0;
  String _gemmaError = '';

  // Model readiness
  bool _whisperReady = false;
  bool _gemmaReady = false;

  // Getters
  DownloadState get whisperState => _whisperState;
  double get whisperProgress => _whisperProgress;
  String get whisperError => _whisperError;
  DownloadState get gemmaState => _gemmaState;
  double get gemmaProgress => _gemmaProgress;
  String get gemmaError => _gemmaError;
  bool get whisperReady => _whisperReady;
  bool get gemmaReady => _gemmaReady;
  bool get allModelsReady => _whisperReady && _gemmaReady;

  Future<void> checkModels() async {
    _whisperReady = await StorageService.whisperModelExists();
    _gemmaReady = await StorageService.gemmaModelExists();

    if (_whisperReady) _whisperState = DownloadState.completed;
    if (_gemmaReady) _gemmaState = DownloadState.completed;

    await StorageService.setWhisperReady(_whisperReady);
    await StorageService.setGemmaReady(_gemmaReady);
    notifyListeners();
  }

  Future<void> downloadWhisper() async {
    if (_whisperState == DownloadState.downloading) return;

    _whisperState = DownloadState.downloading;
    _whisperProgress = 0.0;
    _whisperError = '';
    _whisperCancelToken = CancelToken();
    notifyListeners();

    try {
      final path = await StorageService.whisperModelPath;
      await _downloadFile(
        url: whisperUrl,
        savePath: path,
        cancelToken: _whisperCancelToken!,
        onProgress: (progress) {
          _whisperProgress = progress;
          notifyListeners();
        },
      );

      _whisperState = DownloadState.completed;
      _whisperReady = true;
      await StorageService.setWhisperReady(true);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _whisperState = DownloadState.paused;
      } else {
        _whisperState = DownloadState.error;
        _whisperError = e.message ?? 'Download failed';
      }
    } catch (e) {
      _whisperState = DownloadState.error;
      _whisperError = e.toString();
    }
    notifyListeners();
  }

  Future<void> downloadGemma() async {
    if (_gemmaState == DownloadState.downloading) return;

    _gemmaState = DownloadState.downloading;
    _gemmaProgress = 0.0;
    _gemmaError = '';
    _gemmaCancelToken = CancelToken();
    notifyListeners();

    try {
      final path = await StorageService.gemmaModelPath;
      await _downloadFile(
        url: gemmaUrl,
        savePath: path,
        cancelToken: _gemmaCancelToken!,
        onProgress: (progress) {
          _gemmaProgress = progress;
          notifyListeners();
        },
      );

      _gemmaState = DownloadState.completed;
      _gemmaReady = true;
      await StorageService.setGemmaReady(true);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _gemmaState = DownloadState.paused;
      } else {
        _gemmaState = DownloadState.error;
        _gemmaError = e.message ?? 'Download failed';
      }
    } catch (e) {
      _gemmaState = DownloadState.error;
      _gemmaError = e.toString();
    }
    notifyListeners();
  }

  Future<void> downloadAll() async {
    await Future.wait([
      downloadWhisper(),
      downloadGemma(),
    ]);
  }

  void cancelWhisper() {
    _whisperCancelToken?.cancel('User cancelled');
    _whisperState = DownloadState.paused;
    notifyListeners();
  }

  void cancelGemma() {
    _gemmaCancelToken?.cancel('User cancelled');
    _gemmaState = DownloadState.paused;
    notifyListeners();
  }

  Future<void> _downloadFile({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required Function(double) onProgress,
  }) async {
    await _dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          onProgress(received / total);
        }
      },
      options: Options(
        receiveTimeout: const Duration(minutes: 30),
        sendTimeout: const Duration(minutes: 5),
      ),
    );
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
