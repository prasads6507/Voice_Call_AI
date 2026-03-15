import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RemoteAudioTunnelService extends ChangeNotifier {
  static const _channel = EventChannel('com.stealthanswer.audio/remote_stream');
  StreamSubscription? _subscription;
  bool _isInteracting = false;
  bool _isDisposed = false;

  bool get isInteracting => _isInteracting;

  /// Starts listening to remote call audio stream tapped natively.
  /// Emits PCM 16kHz mono chunks.
  void startTunnel(Function(List<int>) onAudioChunk) {
    if (_isInteracting) return;

    debugPrint('[RemoteAudioTunnel] Subscribing to native remote audio stream...');
    _isInteracting = true;
    notifyListeners();

    _subscription = _channel.receiveBroadcastStream().listen(
      (data) {
        if (data is List<int>) {
          onAudioChunk(data);
        } else if (data is Uint8List) {
          onAudioChunk(data.toList());
        }
      },
      onError: (error) {
        debugPrint('[RemoteAudioTunnel] Stream error: $error');
        stopTunnel();
      },
      onDone: () {
        debugPrint('[RemoteAudioTunnel] Stream done');
        stopTunnel();
      },
    );
  }

  void stopTunnel() {
    if (!_isInteracting) return;
    _subscription?.cancel();
    _subscription = null;
    _isInteracting = false;
    if (!_isDisposed) notifyListeners();
    debugPrint('[RemoteAudioTunnel] Stopped interception');
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopTunnel();
    super.dispose();
  }
}
