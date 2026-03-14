import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';
import 'package:siprix_voip_sdk/accounts_model.dart';
import 'package:siprix_voip_sdk/logs_model.dart';
import 'package:siprix_voip_sdk/network_model.dart';
import 'storage_service.dart';

enum SipConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

enum CallState {
  idle,
  incoming,
  active,
  ended,
}

class SipService extends ChangeNotifier {
  SipConnectionState _connectionState = SipConnectionState.disconnected;
  CallState _callState = CallState.idle;
  String _statusMessage = 'Not connected';
  String _callerNumber = '';
  String _sipAddress = '';
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  int _activeCallId = -1;
  bool _isMuted = false;
  bool _isSpeakerOn = false;

  // Siprix SDK singleton instance
  final SiprixVoipSdk _sdk = SiprixVoipSdk();
  int _accountId = -1;
  bool _initialized = false;

  SipConnectionState get connectionState => _connectionState;
  CallState get callState => _callState;
  String get statusMessage => _statusMessage;
  String get callerNumber => _callerNumber;
  String get sipAddress => _sipAddress;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  int get activeCallId => _activeCallId;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final iniData = InitData();
      iniData.license = ''; // Free/trial mode
      iniData.logLevelFile = LogLevel.none;
      iniData.logLevelIde = LogLevel.info;
      // iniData.enableVideoCall = false; // Bypassing due to missing native method in v1.0.34
      iniData.singleCallMode = true;

      await _sdk.initialize(iniData);
      
      // Set up call listener
      _sdk.callListener = CallStateListener(
        incoming: _onIncomingCall,
        connected: _onCallConnected,
        terminated: _onCallTerminated,
      );

      // Set up account listener
      _sdk.accListener = AccStateListener(
        regStateChanged: _onRegStateChanged,
      );

      _initialized = true;
      debugPrint('[SipService] SDK initialized');
    } catch (e) {
      debugPrint('[SipService] SDK init error: $e');
      _statusMessage = 'SDK initialization failed';
      notifyListeners();
    }
  }

  void _onRegStateChanged(int accId, RegState state, String response) {
    debugPrint('[SipService] RegState: $state response: $response');
    if (state == RegState.success) {
      _connectionState = SipConnectionState.connected;
      _statusMessage = 'Connected';
      _startKeepAlive();
    } else if (state == RegState.failed) {
      _connectionState = SipConnectionState.error;
      _statusMessage = 'Registration failed: $response';
      _scheduleReconnect();
    }
    notifyListeners();
  }

  void _onIncomingCall(int callId, int accId, bool withVideo, String from, String to) {
    debugPrint('[SipService] Incoming call from: $from callId: $callId');
    _activeCallId = callId;
    _callerNumber = from;
    _callState = CallState.incoming;
    notifyListeners();
  }

  void _onCallConnected(int callId, String from, String to, bool withVideo) {
    debugPrint('[SipService] Call connected callId: $callId');
    _callState = CallState.active;
    notifyListeners();
  }

  void _onCallTerminated(int callId, int statusCode) {
    debugPrint('[SipService] Call terminated callId: $callId status: $statusCode');
    _callState = CallState.ended;
    _activeCallId = -1;
    Future.delayed(const Duration(seconds: 2), () {
      _callState = CallState.idle;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<bool> registerAccount({
    required String username,
    required String password,
    required String domain,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    _connectionState = SipConnectionState.connecting;
    _statusMessage = 'Connecting...';
    _sipAddress = '$username@$domain';
    notifyListeners();

    try {
      final accData = AccountModel(
        sipServer: domain,
        sipExtension: username,
        sipPassword: password,
        expireTime: 300,
      );
      accData.sipAuthId = username;
      accData.transport = SipTransport.udp;
      accData.keepAliveTime = 25;
      
      _accountId = await _sdk.addAccount(accData) ?? -1;
      
      if (_accountId >= 0) {
        _connectionState = SipConnectionState.connected;
        _statusMessage = 'Connected';
        _startKeepAlive();
        notifyListeners();
        return true;
      } else {
        _connectionState = SipConnectionState.error;
        _statusMessage = 'Registration failed';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('[SipService] Register error: $e');
      _connectionState = SipConnectionState.error;
      final errMsg = e.toString();
      _statusMessage = 'Error: ${errMsg.length > 50 ? errMsg.substring(0, 50) : errMsg}';
      notifyListeners();
      _scheduleReconnect();
      return false;
    }
  }

  Future<bool> registerFromStorage() async {
    final creds = await StorageService.getSipCredentials();
    if (creds['username']!.isEmpty) return false;
    
    return registerAccount(
      username: creds['username']!,
      password: creds['password']!,
      domain: creds['domain']!,
    );
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _sendKeepAlive(),
    );
  }

  void _sendKeepAlive() {
    // Siprix handles keep-alive internally via keepAliveTime on account
    debugPrint('[SipService] Keep-alive ping');
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _connectionState = SipConnectionState.reconnecting;
    _statusMessage = 'Reconnecting...';
    notifyListeners();

    _reconnectTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) async {
        debugPrint('[SipService] Attempting reconnect...');
        final success = await registerFromStorage();
        if (success) {
          _reconnectTimer?.cancel();
        }
      },
    );
  }

  // Call handling
  Future<void> answerCall() async {
    if (_activeCallId < 0) return;
    
    try {
      await _sdk.accept(_activeCallId, false);
      _callState = CallState.active;
      notifyListeners();
    } catch (e) {
      debugPrint('[SipService] Answer error: $e');
    }
  }

  Future<void> rejectCall() async {
    if (_activeCallId < 0) return;
    
    try {
      await _sdk.reject(_activeCallId, 486); // 486 Busy Here
      _callState = CallState.idle;
      _activeCallId = -1;
      notifyListeners();
    } catch (e) {
      debugPrint('[SipService] Reject error: $e');
    }
  }

  Future<void> endCall() async {
    if (_activeCallId < 0) return;
    
    try {
      await _sdk.bye(_activeCallId);
    } catch (e) {
      debugPrint('[SipService] End call error: $e');
    }
  }

  Future<void> toggleMute() async {
    if (_activeCallId < 0) return;
    
    _isMuted = !_isMuted;
    try {
      await _sdk.muteMic(_activeCallId, _isMuted);
    } catch (e) {
      debugPrint('[SipService] Mute error: $e');
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    // Speaker phone control is handled through platform audio session
    // siprix_voip_sdk doesn't have a direct setSpeakerPhone API
    notifyListeners();
  }

  Future<void> unregister() async {
    _keepAliveTimer?.cancel();
    _reconnectTimer?.cancel();
    
    if (_accountId >= 0) {
      try {
        await _sdk.deleteAccount(_accountId);
      } catch (e) {
        debugPrint('[SipService] Unregister error: $e');
      }
    }

    _connectionState = SipConnectionState.disconnected;
    _statusMessage = 'Disconnected';
    _accountId = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
