import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NENA VoIP Service
// Manages the bidirectional WebRTC call session between the Deaf user and
// a hearing caller. Implements the Telephony Bridge layer from Section 4.3:
//
//   STREAM A (Outbound): Deaf user signs → CLIP → TTS audio → caller's ear
//   STREAM B (Inbound):  Caller speaks  → Whisper ASR → text → avatar screen
//
// Architecture:
//   - WebRTC handles the peer-to-peer media channel (audio + data)
//   - WebSocket (ws://) connects to your Flask/Colab signaling server
//   - RTCDataChannel carries lightweight text tokens (not raw video)
//   - Only text is sent over the network; video is processed on-device
// ─────────────────────────────────────────────────────────────────────────────

enum CallState {
  idle,        // No active call
  connecting,  // Dialing / waiting for answer
  active,      // Call is live
  ended,       // Call finished
  error,       // Something went wrong
}

class VoipService extends ChangeNotifier {
  // ── WebRTC objects ────────────────────────────────────────────────────────
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;       // Carries Swahili text tokens (lightweight)
  MediaStream? _localStream;          // Deaf user's microphone (for TTS audio)
  MediaStream? _remoteStream;         // Caller's audio stream

  // ── WebSocket signaling ───────────────────────────────────────────────────
  // Replace with your actual signaling server URL.
  // When running on Colab + ngrok: 'wss://your-ngrok-url.ngrok-free.app/ws'
  // For local testing:             'ws://10.0.2.2:5000/ws'  (Android emulator)
  static const String _signalingUrl = 'wss://YOUR_SIGNALING_SERVER/ws';

  // ── State ─────────────────────────────────────────────────────────────────
  CallState _callState = CallState.idle;
  String? _remoteUserId;
  String? _callDuration;
  Timer? _callTimer;
  int _callSeconds = 0;

  // ── Streams for the UI to listen to ──────────────────────────────────────
  // Inbound: Swahili text received from caller (drives the avatar)
  final StreamController<String> _inboundTextController =
      StreamController<String>.broadcast();
  Stream<String> get inboundTextStream => _inboundTextController.stream;

  // Call state changes
  final StreamController<CallState> _callStateController =
      StreamController<CallState>.broadcast();
  Stream<CallState> get callStateStream => _callStateController.stream;

  // Remote audio level (for UI visualizer)
  final StreamController<double> _audioLevelController =
      StreamController<double>.broadcast();
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  // ── Getters ───────────────────────────────────────────────────────────────
  CallState get callState => _callState;
  bool get isActive => _callState == CallState.active;
  bool get isConnecting => _callState == CallState.connecting;
  String? get remoteUserId => _remoteUserId;
  String get callDuration => _callDuration ?? '00:00';

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Initiate a call to a hearing user by their ID or phone number.
  /// The signaling server pairs this session with the recipient.
  Future<void> startCall(String targetId) async {
    if (_callState != CallState.idle) return;

    _updateState(CallState.connecting);
    _remoteUserId = targetId;

    try {
      await _initLocalMedia();
      await _createPeerConnection();
      await _createDataChannel();
      await _createAndSendOffer();
      _startCallTimer();
    } catch (e) {
      debugPrint('[VoIP] startCall error: $e');
      _updateState(CallState.error);
    }
  }

  /// Accept an incoming call offer (called from a push notification or
  /// the signaling server's inbound event).
  Future<void> acceptCall(String callerId, Map<String, dynamic> offer) async {
    if (_callState != CallState.idle) return;

    _updateState(CallState.connecting);
    _remoteUserId = callerId;

    try {
      await _initLocalMedia();
      await _createPeerConnection();

      // Set the caller's SDP offer and generate an answer
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Send answer back via signaling server
      _sendSignal({
        'type': 'answer',
        'sdp': answer.sdp,
        'to': callerId,
      });

      _updateState(CallState.active);
      _startCallTimer();
    } catch (e) {
      debugPrint('[VoIP] acceptCall error: $e');
      _updateState(CallState.error);
    }
  }

  /// Send a translated Swahili text token to the hearing caller.
  /// This is Stream A: sign was recognized → text token → caller's TTS.
  /// Only lightweight text is sent over the network (not video).
  void sendSwahiliToken(String swahiliWord) {
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      debugPrint('[VoIP] Data channel not open, cannot send token');
      return;
    }

    final payload = jsonEncode({
      'type': 'swahili_token',
      'word': swahiliWord,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    _dataChannel!.send(RTCDataChannelMessage(payload));
    debugPrint('[VoIP] Sent token: $swahiliWord');
  }

  /// End the active call and clean up all resources.
  Future<void> endCall() async {
    _callTimer?.cancel();
    _callTimer = null;
    _callSeconds = 0;
    _callDuration = null;

    _sendSignal({'type': 'hangup', 'to': _remoteUserId});

    await _dataChannel?.close();
    await _peerConnection?.close();
    await _localStream?.dispose();
    await _remoteStream?.dispose();

    _dataChannel = null;
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
    _remoteUserId = null;

    _updateState(CallState.ended);

    // Reset to idle after brief delay so UI can show "Call ended"
    await Future.delayed(const Duration(seconds: 2));
    _updateState(CallState.idle);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE — Media & Connection Setup
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initLocalMedia() async {
    // Request microphone access. The Deaf user's TTS audio output will be
    // routed through this stream to the caller. Camera is handled separately
    // by the HomeScreen camera plugin (not WebRTC video track).
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,  // We never send raw video — only text tokens
    });
  }

  Future<void> _createPeerConnection() async {
    // ICE servers let WebRTC punch through NAT/firewalls.
    // Using Google's public STUN servers for now.
    // For production: add TURN servers for reliable connectivity over 3G.
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        // Add your TURN server here for production:
        // {
        //   'urls': 'turn:your-turn-server.com:3478',
        //   'username': 'user',
        //   'credential': 'password',
        // }
      ],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(config);

    // Add local audio track to the peer connection
    _localStream!.getAudioTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // Handle incoming audio from the caller (Stream B input)
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        debugPrint('[VoIP] Remote audio stream received');
        // Audio plays automatically via WebRTC's default renderer
      }
    };

    // ICE candidate exchange — required for WebRTC connection
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _sendSignal({
        'type': 'ice_candidate',
        'candidate': candidate.toMap(),
        'to': _remoteUserId,
      });
    };

    // Connection state changes
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[VoIP] Connection state: $state');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _updateState(CallState.active);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _updateState(CallState.error);
          break;
        default:
          break;
      }
    };

    // Data channel events (for inbound text from caller's side)
    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      _dataChannel = channel;
      _setupDataChannelListeners(channel);
    };
  }

  Future<void> _createDataChannel() async {
    final init = RTCDataChannelInit()
      ..ordered = true          // Guarantee token order
      ..maxRetransmits = 3;     // Retry lost packets up to 3 times

    _dataChannel = await _peerConnection!.createDataChannel(
      'swahili_tokens',
      init,
    );

    _setupDataChannelListeners(_dataChannel!);
  }

  void _setupDataChannelListeners(RTCDataChannel channel) {
    channel.onMessage = (RTCDataChannelMessage message) {
      try {
        final data = jsonDecode(message.text) as Map<String, dynamic>;

        if (data['type'] == 'swahili_token') {
          final word = data['word'] as String;
          debugPrint('[VoIP] Received inbound token: $word');

          // Push to Stream B — drives the avatar on the Deaf user's screen
          _inboundTextController.add(word);
        }

        if (data['type'] == 'audio_level') {
          final level = (data['level'] as num).toDouble();
          _audioLevelController.add(level);
        }
      } catch (e) {
        debugPrint('[VoIP] Data channel parse error: $e');
      }
    };

    channel.onDataChannelState = (RTCDataChannelState state) {
      debugPrint('[VoIP] Data channel state: $state');
    };
  }

  Future<void> _createAndSendOffer() async {
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });

    await _peerConnection!.setLocalDescription(offer);

    _sendSignal({
      'type': 'offer',
      'sdp': offer.sdp,
      'to': _remoteUserId,
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE — Signaling (WebSocket to your Flask server)
  // ─────────────────────────────────────────────────────────────────────────

  // NOTE: In a real implementation this would be a persistent WebSocket
  // connection. For simplicity this demo uses HTTP signaling via your
  // existing Flask /signal endpoint. Replace with dart:io WebSocket
  // for production.
  void _sendSignal(Map<String, dynamic> message) {
    // TODO: Replace with actual WebSocket send
    // Example implementation:
    //   _webSocket.sink.add(jsonEncode(message));
    debugPrint('[VoIP] Signal → server: ${message['type']}');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE — Helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _startCallTimer() {
    _callSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callSeconds++;
      final minutes = (_callSeconds ~/ 60).toString().padLeft(2, '0');
      final seconds = (_callSeconds % 60).toString().padLeft(2, '0');
      _callDuration = '$minutes:$seconds';
      notifyListeners();
    });
  }

  void _updateState(CallState state) {
    _callState = state;
    _callStateController.add(state);
    notifyListeners();
    debugPrint('[VoIP] State → $state');
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _inboundTextController.close();
    _callStateController.close();
    _audioLevelController.close();
    _peerConnection?.dispose();
    _localStream?.dispose();
    super.dispose();
  }
}
