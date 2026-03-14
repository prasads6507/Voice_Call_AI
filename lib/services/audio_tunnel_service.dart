import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class AudioTunnelService extends ChangeNotifier {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<List<int>>? _audioStreamSubscription;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Starts capturing 16kHz PCM 16-bit mono audio
  Future<void> startTunnel(Function(List<int>) onAudioChunk) async {
    if (_isRecording) return;

    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        debugPrint('[AudioTunnel] Microphone permission denied');
        return;
      }

      // Start streaming PCM data
      final audioStream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          bitRate: 256000,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _isRecording = true;
      notifyListeners();

      _audioStreamSubscription = audioStream.listen(
        (data) {
          onAudioChunk(data as List<int>);
        },
        onError: (error) {
          debugPrint('[AudioTunnel] Stream error: $error');
          stopTunnel();
        },
        onDone: () {
          debugPrint('[AudioTunnel] Stream done');
          stopTunnel();
        },
      );
      
      debugPrint('[AudioTunnel] Started PCM 16kHz stream');
    } catch (e) {
      debugPrint('[AudioTunnel] Error starting capture: $e');
      _isRecording = false;
      notifyListeners();
    }
  }

  Future<void> stopTunnel() async {
    if (!_isRecording) return;
    
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }
    
    _isRecording = false;
    debugPrint('[AudioTunnel] Stopped stream');
    notifyListeners();
  }

  @override
  void dispose() {
    stopTunnel();
    _audioRecorder.dispose();
    super.dispose();
  }
}
