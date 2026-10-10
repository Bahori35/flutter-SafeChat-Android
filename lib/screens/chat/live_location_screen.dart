import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../services/socket_service.dart';

class LiveLocationScreen extends StatefulWidget {
  final LatLng initialPosition;
  final UserModel peerUser;
  final UserModel currentUser;
  final bool isMyLiveLocation;
  final String? messageId;
  final VoidCallback? onStopSharing;

  const LiveLocationScreen({
    super.key,
    required this.initialPosition,
    required this.peerUser,
    required this.currentUser,
    required this.isMyLiveLocation,
    this.messageId,
    this.onStopSharing,
  });

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  final MapController _mapController = MapController();
  final SocketService _socketService = SocketService();
  
  late LatLng _peerLocation;
  LatLng? _myLocation;
  double _heading = 0.0;
  double _speed = 0.0;
  bool _isLiveActive = true;
  DateTime _lastUpdate = DateTime.now();
  StreamSubscription<Position>? _myGpsSubscription;

  @override
  void initState() {
    super.initState();
    _peerLocation = widget.initialPosition;

    // Track own GPS location
    _trackMyGps();

    // Listen to real-time live location updates from Socket
    _socketService.onLiveLocationUpdate = (data) {
      final senderId = data['senderId']?.toString();
      if (senderId == widget.peerUser.uid) {
        final lat = (data['latitude'] as num?)?.toDouble();
        final lon = (data['longitude'] as num?)?.toDouble();
        final heading = (data['heading'] as num?)?.toDouble() ?? 0.0;
        final speed = (data['speed'] as num?)?.toDouble() ?? 0.0;

        if (lat != null && lon != null && mounted) {
          setState(() {
            _peerLocation = LatLng(lat, lon);
            _heading = heading;
            _speed = speed;
            _lastUpdate = DateTime.now();
            _isLiveActive = true;
          });
        }
      }
    };

    _socketService.onLiveLocationStopped = (data) {
      final senderId = data['senderId']?.toString();
      if (senderId == widget.peerUser.uid && mounted) {
        setState(() {
          _isLiveActive = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.peerUser.displayName} canlı konum paylaşımını durdurdu.'),
            backgroundColor: AppColors.surfaceLight,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    };
  }

  void _trackMyGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      ).catchError((_) => null as dynamic);

      if (pos != null && mounted) {
        setState(() {
          _myLocation = LatLng(pos.latitude, pos.longitude);
        });
      }

      _myGpsSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen((Position position) {
        if (mounted) {
          setState(() {
            _myLocation = LatLng(position.latitude, position.longitude);
          });
          if (widget.isMyLiveLocation) {
            _socketService.emitLiveLocationUpdate(
              senderId: widget.currentUser.uid,
              receiverId: widget.peerUser.uid,
              latitude: position.latitude,
              longitude: position.longitude,
              heading: position.heading,
              speed: position.speed,
              messageId: widget.messageId,
            );
          }
        }
      });
    } catch (e) {
      debugPrint('[LIVE GPS ERROR] $e');
    }
  }

  @override
  void dispose() {
    _myGpsSubscription?.cancel();
    super.dispose();
  }

  void _reCenterToPeer() {
    _mapController.move(_peerLocation, 17.0);
  }

  void _reCenterToMe() {
    if (_myLocation != null) {
      _mapController.move(_myLocation!, 17.0);
    }
  }

  void _openInGoogleMaps() async {
    final url = Uri.parse('https://maps.google.com/?q=${_peerLocation.latitude},${_peerLocation.longitude}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeUser = widget.isMyLiveLocation ? widget.currentUser : widget.peerUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.surfaceLight,
              backgroundImage: CachedNetworkImageProvider(activeUser.photoUrl),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isMyLiveLocation ? 'Canlı Konumunuz' : '${activeUser.displayName} - Canlı Konum',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _isLiveActive ? AppColors.onlineGreen : AppColors.textSecondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isLiveActive ? 'Canlı yayında' : 'Paylaşım sona erdi',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _isLiveActive ? AppColors.onlineGreen : AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: AppColors.primaryLight),
            tooltip: 'Haritada Aç',
            onPressed: _openInGoogleMaps,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Fullscreen Flutter Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _peerLocation,
              initialZoom: 16.5,
              maxZoom: 19.0,
              minZoom: 4.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.talknex.app',
                tileBuilder: (context, tileWidget, tile) {
                  return ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      0.85, 0,    0,    0, -20,
                      0,    0.85, 0,    0, -20,
                      0,    0,    0.85, 0, -20,
                      0,    0,    0,    1,   0,
                    ]),
                    child: tileWidget,
                  );
                },
              ),
              MarkerLayer(
                markers: [
                  // My own location marker if viewing peer
                  if (!widget.isMyLiveLocation && _myLocation != null)
                    Marker(
                      point: _myLocation!,
                      width: 32,
                      height: 32,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.25),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent.withOpacity(0.4),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Live peer / tracked user moving pin
                  Marker(
                    point: _peerLocation,
                    width: 70,
                    height: 80,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Avatar Bubble Pin
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isLiveActive ? AppColors.onlineGreen : const Color(0xFFFF5722),
                              width: 3.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_isLiveActive ? AppColors.onlineGreen : const Color(0xFFFF5722)).withOpacity(0.5),
                                blurRadius: 14,
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: activeUser.photoUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: AppColors.surfaceLight),
                              errorWidget: (_, __, ___) => const Icon(Icons.person, color: Colors.white),
                            ),
                          ),
                        ),
                        // Pin downward arrow indicator
                        CustomPaint(
                          size: const Size(14, 8),
                          painter: _TrianglePainter(
                            color: _isLiveActive ? AppColors.onlineGreen : const Color(0xFFFF5722),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Floating Action Buttons (Recenter buttons)
          Positioned(
            right: 16,
            bottom: widget.isMyLiveLocation ? 95 : 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.isMyLiveLocation && _myLocation != null) ...[
                  FloatingActionButton.small(
                    heroTag: 'my_loc_btn',
                    backgroundColor: AppColors.surface,
                    foregroundColor: Colors.blueAccent,
                    onPressed: _reCenterToMe,
                    child: const Icon(Icons.my_location_rounded),
                  ),
                  const SizedBox(height: 10),
                ],
                FloatingActionButton(
                  heroTag: 'peer_loc_btn',
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  onPressed: _reCenterToPeer,
                  child: const Icon(Icons.person_pin_circle_rounded, size: 28),
                ),
              ],
            ),
          ),

          // Bottom Bar for Stopping Live Location (if it is my live location)
          if (widget.isMyLiveLocation && _isLiveActive)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.onlineGreen.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.sensors_rounded, color: AppColors.onlineGreen, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Canlı Konum Paylaşılıyor',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            Text(
                              'Karşı taraf anlık hareketlerinizi görüyor',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          _socketService.emitStopLiveLocation(
                            senderId: widget.currentUser.uid,
                            receiverId: widget.peerUser.uid,
                            messageId: widget.messageId,
                          );
                          widget.onStopSharing?.call();
                          setState(() {
                            _isLiveActive = false;
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.callRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Durdur', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
