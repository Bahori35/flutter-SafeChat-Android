import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_colors.dart';
import '../../models/call_model.dart';
import '../../models/user_model.dart';
import '../../services/signaling_service.dart';

class CallScreen extends StatefulWidget {
  final UserModel currentUser;
  final UserModel peerUser;
  final CallType callType;
  final bool isCaller;
  final String? callId;

  const CallScreen({
    super.key,
    required this.currentUser,
    required this.peerUser,
    required this.callType,
    required this.isCaller,
    this.callId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final SignalingService _signaling = SignalingService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isSpeaker = true;
  String _callStatusText = 'Bağlanıyor...';
  String? _activeCallId;

  @override
  void initState() {
    super.initState();
    _initRenderersAndCall();
  }

  void _initRenderersAndCall() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    final isVideo = widget.callType == CallType.video;
    await _signaling.openUserMedia(_localRenderer, _remoteRenderer, isVideo: isVideo);

    if (widget.isCaller) {
      setState(() {
        _callStatusText = 'Çalıyor...';
      });

      _activeCallId = await _signaling.makeCall(
        caller: widget.currentUser,
        receiver: widget.peerUser,
        callType: widget.callType,
        localRenderer: _localRenderer,
        remoteRenderer: _remoteRenderer,
      );

      // Listen for remote call status (e.g., rejected / ended)
      _signaling.getCallStream(_activeCallId!).listen((doc) {
        if (!doc.exists) return;
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return;

        final status = data['callStatus'];
        if (status == CallStatus.accepted.name) {
          setState(() {
            _callStatusText = 'Görüşme Başladı';
          });
        } else if (status == CallStatus.ended.name || status == CallStatus.rejected.name) {
          _hangUp();
        }
      });
    } else {
      // Receiver answers call
      _activeCallId = widget.callId;
      if (_activeCallId != null) {
        await _signaling.answerCall(
          callId: _activeCallId!,
          localRenderer: _localRenderer,
          remoteRenderer: _remoteRenderer,
        );
        setState(() {
          _callStatusText = 'Görüşme Başladı';
        });

        _signaling.getCallStream(_activeCallId!).listen((doc) {
          if (!doc.exists) return;
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return;
          if (data['callStatus'] == CallStatus.ended.name) {
            _hangUp();
          }
        });
      }
    }
  }

  void _toggleMic() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _signaling.localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
  }

  void _toggleVideo() {
    setState(() {
      _isVideoOff = !_isVideoOff;
    });
    _signaling.localStream?.getVideoTracks().forEach((track) {
      track.enabled = !_isVideoOff;
    });
  }

  void _switchCamera() {
    Helper.switchCamera(_signaling.localStream!.getVideoTracks()[0]);
  }

  void _hangUp() async {
    await _signaling.endCall(_activeCallId);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _signaling.endCall(_activeCallId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == CallType.video;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Video / Audio View
            if (isVideo) ...[
              // Remote Fullscreen Video
              Positioned.fill(
                child: RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),

              // Local Picture-in-Picture Video
              Positioned(
                right: 20,
                top: 30,
                width: 110,
                height: 160,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ] else ...[
              // Audio Call UI
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 65,
                      backgroundImage: CachedNetworkImageProvider(widget.peerUser.photoUrl),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.peerUser.displayName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _callStatusText,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Top Caller Info Banner (when in video call)
            if (isVideo)
              Positioned(
                top: 24,
                left: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.peerUser.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                      ),
                    ),
                    Text(
                      _callStatusText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                      ),
                    ),
                  ],
                ),
              ),

            // Bottom Action Controls
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute Audio
                    IconButton(
                      icon: Icon(
                        _isMuted ? Icons.mic_off : Icons.mic,
                        color: _isMuted ? AppColors.callRed : Colors.white,
                        size: 28,
                      ),
                      onPressed: _toggleMic,
                    ),

                    // Toggle Video / Switch Camera
                    if (isVideo) ...[
                      IconButton(
                        icon: Icon(
                          _isVideoOff ? Icons.videocam_off : Icons.videocam,
                          color: _isVideoOff ? AppColors.callRed : Colors.white,
                          size: 28,
                        ),
                        onPressed: _toggleVideo,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.cameraswitch,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: _switchCamera,
                      ),
                    ],

                    // End Call
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.callRed,
                      child: IconButton(
                        icon: const Icon(Icons.call_end, color: Colors.white, size: 28),
                        onPressed: _hangUp,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
