import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../constants/app_colors.dart';

class LocationPickerResult {
  final double latitude;
  final double longitude;
  final String title;
  final String address;
  final bool isLive;

  LocationPickerResult({
    required this.latitude,
    required this.longitude,
    required this.title,
    required this.address,
    this.isLive = false,
  });
}

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;

  const LocationPickerScreen({super.key, this.initialLocation});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  late LatLng _currentLocation;
  late LatLng _selectedLocation;
  bool _isLoadingGps = true;
  bool _isSearchingAddress = false;
  String _selectedAddress = 'Konum alınıyor...';
  String _selectedTitle = 'Konumunuz';

  @override
  void initState() {
    super.initState();
    if (widget.initialLocation != null) {
      _currentLocation = widget.initialLocation!;
      _selectedLocation = widget.initialLocation!;
      _isLoadingGps = false;
      _reverseGeocode(widget.initialLocation!);
    } else {
      _currentLocation = const LatLng(39.925533, 32.866287);
      _selectedLocation = _currentLocation;
      _getCurrentGpsLocation();
    }
  }

  Future<void> _getCurrentGpsLocation() async {
    setState(() {
      _isLoadingGps = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lütfen GPS / Konum servisini etkinleştirin.'),
              backgroundColor: AppColors.callRed,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() => _isLoadingGps = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoadingGps = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLoadingGps = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      final newPos = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentLocation = newPos;
          _selectedLocation = newPos;
          _isLoadingGps = false;
        });
        _mapController.move(newPos, 16.0);
        _reverseGeocode(newPos);
      }
    } catch (e) {
      debugPrint('[GPS ERROR] $e');
      if (mounted) {
        setState(() {
          _isLoadingGps = false;
        });
      }
    }
  }

  // Reverse geocoding with OpenStreetMap Nominatim API
  Future<void> _reverseGeocode(LatLng pos) async {
    setState(() {
      _isSearchingAddress = true;
    });

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}&zoom=18&addressdetails=1',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'TalknexMessengerApp/1.0',
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final displayName = data['display_name'] ?? 'Konum detayı';
        final addressObj = data['address'] ?? {};
        
        final road = addressObj['road'] ?? addressObj['neighbourhood'] ?? addressObj['suburb'] ?? 'İşaretlenen Nokta';
        final city = addressObj['city'] ?? addressObj['town'] ?? addressObj['county'] ?? addressObj['state'] ?? '';

        if (mounted) {
          setState(() {
            _selectedTitle = road;
            _selectedAddress = '$road, $city'.trim();
            if (_selectedAddress.endsWith(',')) {
              _selectedAddress = _selectedAddress.substring(0, _selectedAddress.length - 1);
            }
            if (_selectedAddress.isEmpty) _selectedAddress = displayName;
            _isSearchingAddress = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _selectedTitle = 'İşaretlenen Nokta';
            _selectedAddress = 'Enlem: ${pos.latitude.toStringAsFixed(5)}, Boylam: ${pos.longitude.toStringAsFixed(5)}';
            _isSearchingAddress = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedTitle = 'İşaretlenen Nokta';
          _selectedAddress = 'Enlem: ${pos.latitude.toStringAsFixed(5)}, Boylam: ${pos.longitude.toStringAsFixed(5)}';
          _isSearchingAddress = false;
        });
      }
    }
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture) {
      final center = camera.center;
      setState(() {
        _selectedLocation = center;
      });
    }
  }

  void _onMapMoveEnd() {
    _reverseGeocode(_selectedLocation);
  }

  void _sendSelectedLocation({bool isLive = false}) {
    final result = LocationPickerResult(
      latitude: _selectedLocation.latitude,
      longitude: _selectedLocation.longitude,
      title: isLive ? 'Mevcut Canlı Konum' : _selectedTitle,
      address: _selectedAddress,
      isLive: isLive,
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        title: const Text(
          'Konum Gönder',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location_rounded, color: AppColors.primaryLight),
            tooltip: 'Mevcut Konumuma Git',
            onPressed: _getCurrentGpsLocation,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Flutter OpenStreetMap Widget
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 16.0,
              maxZoom: 19.0,
              minZoom: 4.0,
              onPositionChanged: _onMapPositionChanged,
              onMapEvent: (evt) {
                if (evt is MapEventMoveEnd) {
                  _onMapMoveEnd();
                }
              },
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
                  // GPS current user pulse marker
                  Marker(
                    point: _currentLocation,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Center Interactive Pin (WhatsApp style pin with float animation)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 42.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.touch_app_rounded, color: AppColors.accent, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _isSearchingAddress ? 'Adres bulunuyor...' : _selectedTitle,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3D00),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF3D00).withOpacity(0.5),
                          blurRadius: 12,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 28),
                  ),
                  // Pin tip shadow
                  Container(
                    width: 8,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top Floating Search / Location Card
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.pin_drop_rounded, color: AppColors.primaryLight, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedTitle,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedAddress,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Action Sheet (WhatsApp Style)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.cardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Option 1: Live Location (Continuous dynamic sharing)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        setState(() {
                          _selectedLocation = _currentLocation;
                        });
                        _sendSelectedLocation(isLive: true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.onlineGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.onlineGreen.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: AppColors.onlineGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.sensors_rounded, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Canlı Konum Paylaş',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Hareket ettikçe anlık olarak güncellensin',
                                    style: TextStyle(
                                      color: AppColors.onlineGreen,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.onlineGreen, size: 16),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Option 2: Send Current GPS Fixed Location (Static)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        setState(() {
                          _selectedLocation = _currentLocation;
                        });
                        _sendSelectedLocation(isLive: false);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Şu Anki Konumumu Gönder',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Bulunduğunuz sabit GPS noktasını yollar (Statik)',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.send_rounded, color: AppColors.accent, size: 20),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Option 3: Send Marked Pin Location (Static)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _sendSelectedLocation(isLive: false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5722).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFF5722).withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF5722),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.pin_drop_rounded, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Haritada İşaretlenen Konumu Gönder',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFFF7043),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFFF5722), size: 16),
                          ],
                        ),
                      ),
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
