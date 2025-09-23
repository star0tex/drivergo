import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/driver_socket_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/socket_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class DriverDashboardPage extends StatefulWidget {
  final String driverId;
  final String vehicleType;

  const DriverDashboardPage({
    Key? key,
    required this.driverId,
    required this.vehicleType,
  }) : super(key: key);

  @override
  _DriverDashboardPageState createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends State<DriverDashboardPage> {
  final String apiBase = 'http://192.168.1.28:5002';
  final DriverSocketService _socketService = DriverSocketService();

  bool isOnline = false;
  bool acceptsLong = false;
  List<Map<String, dynamic>> rideRequests = [];
  Map<String, dynamic>? currentRide;
  Map<String, dynamic>? confirmedRide;

  GoogleMapController? _googleMapController;
  late String driverId;

  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  LatLng? _customerPickup;
  Timer? _locationUpdateTimer;
  Timer? _cleanupTimer;
  final Set<String> _seenTripIds = {};

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? driverFcmToken;

  @override
  void initState() {
    super.initState();
    driverId = widget.driverId;
    _requestLocationPermission();
    _getCurrentLocation();
    _initSocketAndFCM();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
    if (_seenTripIds.length > 100) {
      // Keep only the most recent 50 trip IDs
      final recentIds = _seenTripIds.toList().sublist(_seenTripIds.length - 50);
      _seenTripIds.clear();
      _seenTripIds.addAll(recentIds);
      print("🧹 Cleaned up old trip IDs, kept ${_seenTripIds.length} recent ones");
    }
  });
  }
 double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return null;
      return double.tryParse(s);
    }
    return null;
  }
 Future<void> _initSocketAndFCM() async {
  driverFcmToken = await FirebaseMessaging.instance.getToken();
  final pos = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );
  setState(() {
    _currentPosition = LatLng(pos.latitude, pos.longitude);
  });

  _socketService.connect(
    driverId,
    pos.latitude,
    pos.longitude,
    vehicleType: widget.vehicleType,
    isOnline: isOnline,
    fcmToken: driverFcmToken,
  );

  // ✅ SOCKET is PRIMARY - handle trip requests immediately
  _socketService.socket.on('trip:request', (data) {
    print("📥 [SOCKET-PRIMARY] trip:request received: $data");
    _playNotificationSound();
    _handleIncomingTrip(data);
  });

  _socketService.socket.on('tripRequest', (data) {
    print("📥 [SOCKET-PRIMARY] tripRequest received: $data (legacy)");
    _playNotificationSound();
    _handleIncomingTrip(data);
  });

  // ✅ FCM is BACKUP - handle with delay to allow socket first
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print("📩 [FCM-BACKUP] Foreground FCM received: ${message.data}");

    // Add delay to allow socket to handle first (2 seconds)
    Future.delayed(const Duration(seconds: 2), () {
      // Check if this trip hasn't been handled by socket already
      final tripId = message.data['tripId']?.toString();
      if (tripId != null && !_seenTripIds.contains(tripId)) {
        _playNotificationSound();
        
        // Normalize FCM data
        final Map<String, dynamic> tripData = message.data.map((key, value) {
          try {
            return MapEntry(key, jsonDecode(value));
          } catch (e) {
            return MapEntry(key, value);
          }
        });
        
        _handleIncomingTrip(tripData);
      } else if (tripId != null) {
        print("⚠️ [FCM-BACKUP] Duplicate trip ignored (already handled by socket): $tripId");
      }
    });
  });

  // ✅ FCM when tapped from tray (background/terminated)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print("📩 [FCM-BACKUP] Notification tapped: ${message.data}");

    // Add delay to prevent duplicates
    Future.delayed(const Duration(seconds: 1), () {
      final tripId = message.data['tripId']?.toString();
      if (tripId != null && !_seenTripIds.contains(tripId)) {
        _playNotificationSound();
        
        // Normalize FCM data
        final Map<String, dynamic> tripData = message.data.map((key, value) {
          try {
            return MapEntry(key, jsonDecode(value));
          } catch (e) {
            return MapEntry(key, value);
          }
        });
        
        _handleIncomingTrip(tripData);
      } else if (tripId != null) {
        print("⚠️ [FCM-BACKUP] Duplicate trip ignored (already handled): $tripId");
      }
    });
  });

  _socketService.onRideConfirmed = (data) {
    print('✅ Ride confirmed: $data');
    if (mounted) {
      _playNotificationSound();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ride confirmed!')));
    }
    _handleRideConfirmation(data);
  };

  _socketService.onRideCancelled = (data) {
    print('❌ Ride cancelled: $data');
    if (mounted) {
      _playNotificationSound();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ride cancelled.')));
    }
  };
}

void _handleIncomingTrip(dynamic rawData) {
  print("📥 Raw incoming trip: $rawData");

  Map<String, dynamic> request;

  try {
    if (rawData is String) {
      request = jsonDecode(rawData) as Map<String, dynamic>;
    } else if (rawData is Map) {
      request = Map<String, dynamic>.from(rawData);
    } else {
      print("❌ Unsupported trip data format: $rawData");
      return;
    }

    // ✅ Normalize pickup/drop
    if (request['pickup'] is String) {
      try {
        request['pickup'] = jsonDecode(request['pickup']);
      } catch (e) {
        print("⚠️ Could not parse pickup as JSON: ${request['pickup']}");
      }
    }
    if (request['drop'] is String) {
      try {
        request['drop'] = jsonDecode(request['drop']);
      } catch (e) {
        print("⚠️ Could not parse drop as JSON: ${request['drop']}");
      }
    }
  } catch (e) {
    print("❌ Failed to parse trip data: $e");
    return;
  }

  // ✅ Extract trip ID for duplicate checking
  final tripId = request['tripId']?.toString() ?? request['_id']?.toString();
  if (tripId == null) {
    print("❌ No tripId found in request");
    return;
  }

  // ✅ STRONG DEDUPLICATION - Check if already in seen IDs or queue
  final isDuplicate = _seenTripIds.contains(tripId) || 
                     rideRequests.any((req) {
                       final existingTripId = req['tripId']?.toString() ?? req['_id']?.toString();
                       return existingTripId == tripId;
                     });

  if (isDuplicate) {
    print("⚠️ Duplicate trip ignored: $tripId");
    return;
  }

  // ✅ Add to seen trip IDs to prevent future duplicates
  _seenTripIds.add(tripId);
  print("✅ Added trip to seen IDs: $tripId");

  print("✅ Normalized trip request: $request");

  if (!isOnline) {
    print("❌ Ignored because driver is off duty");
    return;
  }

  String requestVehicleType =
      (request['vehicleType'] ?? '').toString().toLowerCase().trim();
  String driverVehicleType = widget.vehicleType.toLowerCase().trim();

  if (requestVehicleType != driverVehicleType) {
    print("🚫 Vehicle type mismatch. Expected: $driverVehicleType, Got: $requestVehicleType");
    return;
  }

  setState(() {
    rideRequests.add(request);
    currentRide = rideRequests.isNotEmpty ? rideRequests.first : null;
  });

  _playNotificationSound();
  _showIncomingTripPopup(request);
}
void _debugCurrentState() {
  print("🔍 DEBUG - Current State:");
  print("   Online: $isOnline");
  print("   Current Ride: ${currentRide != null}");
  print("   Confirmed Ride: ${confirmedRide != null}");
  print("   Ride Requests in Queue: ${rideRequests.length}");
  print("   Seen Trip IDs: ${_seenTripIds.length}");
  
  if (currentRide != null) {
    final tripId = currentRide!['tripId']?.toString() ?? currentRide!['_id']?.toString();
    print("   Current Trip ID: $tripId");
  }
}

// Call this method when needed for debugging
// _debugCurrentState();
void _showIncomingTripPopup(Map<String, dynamic> request) {
  showModalBottomSheet(
    context: context,
    isDismissible: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.local_taxi, color: Colors.blue, size: 28),
                SizedBox(width: 10),
                Text(
                  "New Ride Request",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text("Pickup: ${request['pickup']?['address'] ?? ''}",
                style: const TextStyle(fontSize: 16)),
            Text("Drop: ${request['drop']?['address'] ?? ''}",
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.cancel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    rejectRide();
                  },
                  label: const Text("Reject"),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    acceptRide();
                  },
                  label: const Text("Accept"),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}


  void _handleRideConfirmation(dynamic data) {
    print("✅ Ride confirmation received: $data");

    // First check if driver is on duty
    if (!isOnline) {
      print("❌ Ignored confirmation because driver is off duty");
      return;
    }

    final confirmation = Map<String, dynamic>.from(data);

    // Update the confirmed ride state
    setState(() {
      confirmedRide = confirmation;
    });

    // Show notification for the confirmed ride
    _showRideConfirmationNotification(confirmation);
  }

  void _playNotificationSound() async {
    // 🔔 Added
    await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
  }

  void _stopNotificationSound() async {
    // 🔔 Added
    await _audioPlayer.stop();
  }

  void _showRideConfirmationNotification(Map<String, dynamic> confirmation) {
    // Play notification sound
    _playNotificationSound();

    // Show a snackbar with the confirmation details
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ride confirmed! ${confirmation['message'] ?? 'Customer has confirmed the ride.'}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            // Show more details or navigate to ride details
            _showRideConfirmationDetails(confirmation);
          },
        ),
      ),
    );
  }

  void _showRideConfirmationDetails(Map<String, dynamic> confirmation) {
    // Show a dialog with detailed information about the confirmed ride
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Ride Confirmed',
          style: TextStyle(color: Colors.green),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ride ID: ${confirmation['rideId'] ?? confirmation['id'] ?? 'N/A'}',
              ),
              const SizedBox(height: 8),
              Text(
                'Customer: ${confirmation['userName'] ?? confirmation['customerName'] ?? 'N/A'}',
              ),
              const SizedBox(height: 8),
              Text(
                'Pickup: ${_getAddressFromConfirmation(confirmation, 'pickup')}',
              ),
              const SizedBox(height: 8),
              Text(
                'Destination: ${_getAddressFromConfirmation(confirmation, 'drop')}',
              ),
              const SizedBox(height: 8),
              Text('Payment: ${confirmation['paymentMethod'] ?? 'Cash'}'),
              const SizedBox(height: 8),
              Text(
                'Amount: ₹${confirmation['fare'] ?? confirmation['amount'] ?? 'N/A'}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              // Navigate to the ride details or update the map
              _handleConfirmedRide(confirmation);
            },
            child: const Text('NAVIGATE'),
          ),
        ],
      ),
    );
  }

  String _getAddressFromConfirmation(
    Map<String, dynamic> confirmation,
    String type,
  ) {
    if (confirmation[type] != null) {
      if (confirmation[type] is Map) {
        return confirmation[type]['address'] ?? 'N/A';
      } else {
        return confirmation[type].toString();
      }
    }
    return 'N/A';
  }

  void _handleConfirmedRide(Map<String, dynamic> confirmation) {
    // Update the map with the confirmed ride details
    // This could include drawing a route to the pickup location
    try {
      // Extract pickup location from confirmation
      double? pickupLat, pickupLng;

      if (confirmation['pickup'] is Map) {
        pickupLat =
            double.tryParse(confirmation['pickup']['lat']?.toString() ?? '') ??
            double.tryParse(
              confirmation['pickup']['latitude']?.toString() ?? '',
            );
        pickupLng =
            double.tryParse(confirmation['pickup']['lng']?.toString() ?? '') ??
            double.tryParse(
              confirmation['pickup']['longitude']?.toString() ?? '',
            );
      }

      if (pickupLat != null && pickupLng != null) {
        // Set customer pickup location
        _customerPickup = LatLng(pickupLat, pickupLng);

        // Draw route to customer
        _drawRouteToCustomer();

        // Start location updates
        _startLiveLocationUpdates();

        // Show action buttons for the confirmed ride
        _showRideActionButtons(confirmation);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Navigating to pickup location')),
        );
      } else {
        print(
          '❌ Could not extract pickup location from confirmation: $confirmation',
        );
      }
    } catch (e) {
      print('❌ Error handling confirmed ride: $e');
    }
  }

  void _showRideActionButtons(Map<String, dynamic> confirmation) {
    // Show a bottom sheet with ride action buttons
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ride to ${_getAddressFromConfirmation(confirmation, "destination")}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Complete Ride'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    _completeRide(confirmation);
                    Navigator.pop(context);
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel Ride'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    _cancelRide(confirmation);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _completeRide(Map<String, dynamic> confirmation) {
    try {
      final String rideId = confirmation['_id'] ?? confirmation['id'] ?? '';
      if (rideId.isEmpty) {
        print('❌ Cannot complete ride: Missing ride ID');
        return;
      }

      // Get driver ID from the socket service
      final String? driverId = widget.driverId;
      if (driverId == null || driverId.isEmpty) {
        print('❌ Cannot complete ride: Missing driver ID');
        return;
      }

      // Call the socket service to complete the ride
      _socketService.completeRide(driverId, rideId);
      print('✅ Called completeRide with driverId: $driverId, rideId: $rideId');

      // Clear the confirmed ride from state
      _clearConfirmedRide();

      // Clear the route and markers
      _clearRouteAndMarkers();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride completed successfully')),
      );
    } catch (e) {
      print('❌ Error completing ride: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to complete ride')));
    }
  }

  void _cancelRide(Map<String, dynamic> confirmation) {
    try {
      // Clear the confirmed ride from state
      _clearConfirmedRide();

      // Clear the route and markers
      _clearRouteAndMarkers();

      // Show message
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ride cancelled')));
    } catch (e) {
      print('❌ Error cancelling ride: $e');
    }
  }

  void _clearRouteAndMarkers() {
    setState(() {
      _polylines.clear();
      _markers.clear();
      _customerPickup = null;
    });
  }

  void _clearConfirmedRide() {
    setState(() {
      confirmedRide = null;
    });
    print('🧹 Cleared confirmed ride from state');
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required to use map.'),
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> verifyDriverWithBackend(
    String vehicleType,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final idToken = await user.getIdToken(); // Firebase ID token

    final response = await http.post(
      Uri.parse('http://192.168.1.28:5002/api/driver/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'firebaseIdToken': idToken,
        'vehicleType': vehicleType,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body); // { driverId, vehicleType }
    } else {
      print("❌ Driver login failed: ${response.body}");
      return null;
    }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permissions are permanently denied'),
        ),
      );
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _mapController?.animateCamera(CameraUpdate.newLatLng(_currentPosition!));
    });
  }

void acceptRide() async {
  if (currentRide == null) return;

  _stopNotificationSound();

  print('✅ Driver accepting ride: ${currentRide!['tripId']}');
  
  // ✅ FIX: Use the correct tripId parameter name
  final tripId = currentRide!['tripId'] ?? currentRide!['_id'];
  if (tripId == null) {
    print('❌ No tripId found in currentRide: $currentRide');
    return;
  }

  // ✅ FIX: Use proper socket emission with correct parameters
  _socketService.socket.emit('driver:accept_trip', {
    'tripId': tripId.toString(),
    'driverId': driverId,
  });

  print('📤 Emitted driver:accept_trip event:');
  print('   - tripId: $tripId');
  print('   - driverId: $driverId');

  // Fetch customer pickup location
  final customerId = currentRide!['customerId'] ?? currentRide!['userId'];
  if (customerId != null) {
    await _fetchCustomerPickupLocation(customerId.toString());
  }

  // Draw navigation route
  await _drawRouteToCustomer();

  // Start sending driver live location updates
  _startLiveLocationUpdates();

  // Show confirmation to driver
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("Ride Accepted!")),
  );

  // Remove current ride request from queue
  setState(() {
    currentRide = rideRequests.isNotEmpty ? rideRequests.removeAt(0) : null;
    if (currentRide != null) _playNotificationSound();
  });
}  void _startLiveLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      if (_currentPosition == null) return;
      final pos = await Geolocator.getCurrentPosition();
      _currentPosition = LatLng(pos.latitude, pos.longitude);
      _updateDriverStatusSocket();
      _sendLocationToBackend(pos.latitude, pos.longitude);
    });
  }

  Future<void> _sendLocationToBackend(double lat, double lng) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBase/api/location/updateDriver'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
  'driverId': driverId,
  'latitude': lat,
  'longitude': lng,
  'tripId': confirmedRide?['tripId'] ?? confirmedRide?['_id'], // ✅ send tripId if ride accepted
}),

      );

      print("📍 Driver location sent: $lat, $lng");

      if (response.statusCode != 200) {
        print(
          "❌ Server responded with: ${response.statusCode}, ${response.body}",
        );
      }
    } catch (e) {
      print("❌ Error sending driver location: $e");
    }
  }

  LatLng? _pickupLocation;

  Future<void> _fetchCustomerPickupLocation(String customerId) async {
    try {
      final res = await http.get(
        Uri.parse('$apiBase/api/location/customer/$customerId'),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final pickupLatLng = LatLng(data['latitude'], data['longitude']);

        setState(() {
          _markers.removeWhere((m) => m.markerId.value == 'pickup');
          _markers.add(
            Marker(
              markerId: const MarkerId('pickup'),
              position: pickupLatLng,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
            ),
          );
          _pickupLocation = pickupLatLng;
          _customerPickup = pickupLatLng; // ✅ FIX for route drawing
        });

        _googleMapController?.animateCamera(
          CameraUpdate.newLatLngZoom(pickupLatLng, 15),
        );
      } else {
        print("❌ Failed to fetch customer location: ${res.body}");
      }
    } catch (e) {
      print("❌ Error fetching customer pickup location: $e");
    }
  }

  Future<void> _drawRouteToCustomer() async {
    if (_currentPosition == null || _customerPickup == null) return;

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
      '&destination=${_customerPickup!.latitude},${_customerPickup!.longitude}'
      '&key=AIzaSyCqfjktNhxjKfM-JmpSwBk9KtgY429QWY8',
    );

    List<LatLng> polylinePoints = [];

    try {
      final response = await http.get(url);
      if (response.statusCode != 200) {
        print("❌ Failed to get directions: ${response.statusCode}");
        return;
      }

      final data = jsonDecode(response.body);
      if (data['status'] != 'OK' || data['routes'].isEmpty) {
        print("❌ No routes found: ${data['status']}");
        return;
      }

      final encodedPolyline = data['routes'][0]['overview_polyline']['points'];
      polylinePoints = _decodePolyline(encodedPolyline);
    } catch (e) {
      print("❌ Error drawing route: $e");
      return;
    }

    setState(() {
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('routeToCustomer'),
          points: polylinePoints,
          color: Colors.blue,
          width: 5,
        ),
      );
    });

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        _calculateBounds(_currentPosition!, _customerPickup!),
        80,
      ),
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  LatLngBounds _calculateBounds(LatLng p1, LatLng p2) {
    return LatLngBounds(
      southwest: LatLng(
        p1.latitude < p2.latitude ? p1.latitude : p2.latitude,
        p1.longitude < p2.longitude ? p1.longitude : p2.longitude,
      ),
      northeast: LatLng(
        p1.latitude > p2.latitude ? p1.latitude : p2.latitude,
        p1.longitude > p2.longitude ? p1.longitude : p2.longitude,
      ),
    );
  }

 @override
void dispose() {
  _cleanupTimer?.cancel();
  _locationUpdateTimer?.cancel();
  _mapController?.dispose();
  _socketService.disconnect();
  _stopNotificationSound();
  super.dispose();
}

  void rejectRide() {
    if (currentRide == null) return;

    _stopNotificationSound();
    _socketService.rejectRide(
      driverId,
      currentRide!['rideId'] ?? currentRide!['id'] ?? '',
    );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Ride Rejected.")));

    setState(() {
      currentRide = rideRequests.isNotEmpty ? rideRequests.removeAt(0) : null;
      if (currentRide != null) _playNotificationSound();
    });
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    drawer: buildDrawer(),
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      iconTheme: const IconThemeData(color: Colors.black),
      title: Row(
        children: [
          Text(
            isOnline ? "ON DUTY" : "OFF DUTY",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isOnline ? Colors.blue : Colors.red,
                ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: isOnline,
            activeColor: Colors.blue,
            inactiveThumbColor: Colors.grey,
            onChanged: (value) async {
              setState(() => isOnline = value);
              if (!isOnline) acceptsLong = false;
              _updateDriverStatusSocket();
            },
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.location_on_outlined, color: Colors.black),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.notifications_none, color: Colors.black),
          onPressed: () {},
        ),
        const SizedBox(width: 10),
      ],
    ),
    body: Stack(
      children: [
        isOnline ? buildGoogleMap() : buildOffDutyUI(),
        if (confirmedRide != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade600.withOpacity(0.95),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6)
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ride confirmed: ${_getAddressFromConfirmation(confirmedRide!, "pickup")}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.navigation, color: Colors.white),
                    onPressed: () => _handleConfirmedRide(confirmedRide!),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _clearConfirmedRide,
                  ),
                ],
              ),
            ),
          ),
        // ❌ REMOVED: if (currentRide != null) buildRideRequestCard(),
        if (_pickupLocation != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Navigate to Customer Pickup Location",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      final lat = _pickupLocation!.latitude;
                      final lng = _pickupLocation!.longitude;
                      final googleMapsUrl =
                          "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving";
                      launchUrl(
                        Uri.parse(googleMapsUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: const Text(
                      "Go to Pickup",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
Widget buildGoogleMap() {
  LatLng center = _currentPosition != null
      ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
      : const LatLng(17.385044, 78.486671); // fallback Hyderabad

  return GoogleMap(
    initialCameraPosition: CameraPosition(
      target: center,
      zoom: 14,
    ),
    myLocationEnabled: true,
    myLocationButtonEnabled: true,
    zoomControlsEnabled: false,
    markers: {
      if (_pickupLocation != null)
        Marker(
          markerId: const MarkerId("pickup"),
          position: LatLng(
            _pickupLocation!.latitude,
            _pickupLocation!.longitude,
          ),
          infoWindow: const InfoWindow(title: "Pickup"),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      if (currentRide != null && currentRide!['drop'] != null)
  Marker(
    markerId: const MarkerId("drop"),
    position: LatLng(
      _parseDouble(currentRide!['drop']['lat']) ?? 0.0,
      _parseDouble(currentRide!['drop']['lng']) ?? 0.0,
    ),
    infoWindow: InfoWindow(
      title: currentRide!['drop']['address'] ?? "Drop",
    ),
    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
  ),

    },
    onMapCreated: (controller) {
      _googleMapController = controller;
    },
  );
}

Widget buildRideRequestCard() {
  if (currentRide == null) return const SizedBox();

  return Align(
    alignment: Alignment.bottomCenter,
    child: Card(
      margin: const EdgeInsets.all(16),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_taxi, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  "New Ride Request",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                ),
                const Spacer(),
                if (rideRequests.isNotEmpty)
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.red,
                    child: Text(
                      "${rideRequests.length + 1}",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Pickup: ${currentRide!['pickup']['address'] ?? ''}",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              "Drop: ${currentRide!['drop']['address'] ?? ''}",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: rejectRide,
                  child: const Text("Reject"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: acceptRide,
                  child: const Text("Accept"),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget buildOffDutyUI() {
  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      buildEarningsCard(),
      const SizedBox(height: 16),
      buildPerformanceCard(),
      const SizedBox(height: 30),
      Image.asset('assets/mobile.png', height: 140),
      const SizedBox(height: 20),
      Center(
        child: Text(
          "Start the engine, chase the earnings!",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      const SizedBox(height: 10),
      Center(
        child: Text(
          "Go ON DUTY to start earning",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
        ),
      ),
    ],
  );
}

Widget buildDrawer() {
  return Drawer(
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          decoration: BoxDecoration(
            color: Colors.blue.shade600,
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundImage: AssetImage('assets/profile.jpg'),
                radius: 30,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    "My Profile",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "-- ⭐",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  "Best",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),

        // Earnings
        buildDrawerItem(
          Icons.account_balance_wallet,
          "Earnings",
          "Transfer Money to Bank, History",
          iconColor: Colors.blue.shade600,
        ),
        buildDrawerItem(
          Icons.attach_money,
          "Incentives and More",
          "Know how you get paid",
          iconColor: Colors.blue.shade600,
        ),
        buildDrawerItem(
          Icons.card_giftcard,
          "Rewards",
          "Insurance and Discounts",
          iconColor: Colors.blue.shade600,
        ),

        const Divider(),

        buildDrawerItem(
          Icons.view_module,
          "Service Manager",
          "Food Delivery & more",
          iconColor: Colors.blue.shade600,
        ),
        buildDrawerItem(
          Icons.map,
          "Demand Planner",
          "Past High Demand Areas",
          iconColor: Colors.blue.shade600,
        ),
        buildDrawerItem(
          Icons.headset_mic,
          "Help",
          "Support, Accident Insurance",
          iconColor: Colors.blue.shade600,
        ),

        // Refer friends
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.emoji_people, color: Colors.blue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Refer friends & Earn up to ₹",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                  ),
                  child: const Text("Refer Now"),
                ),
              ],
            ),
          ),
        ),

        // Long Trip Toggle (only for car)
        if (widget.vehicleType.toLowerCase() == 'car')
          ListTile(
            title: const Text("Accept Long Trips"),
            trailing: Switch(
              activeColor: Colors.blue,
              value: acceptsLong,
              onChanged: isOnline
                  ? (value) {
                      setState(() => acceptsLong = value);
                      _updateDriverStatusSocket();
                    }
                  : null,
            ),
          ),
      ],
    ),
  );
}

Widget buildDrawerItem(
  IconData icon,
  String title,
  String subtitle, {
  Color iconColor = Colors.black54,
}) {
  return ListTile(
    leading: Icon(icon, color: iconColor),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    onTap: () {},
  );
}

 void _updateDriverStatusSocket() {
  // Get complete profile data
  final driverProfileData = {
    'name': "Ramesh Kumar", // Replace with actual driver name
    'photoUrl': "https://example.com/photo.jpg", // Replace with actual photo URL
    'rating': 4.9,
    'vehicleBrand': "Honda Activa", // Replace with actual vehicle
    'vehicleNumber': "TS09AB1234", // Replace with actual number
    'vehicleType': widget.vehicleType.toLowerCase(),
    'phone': '+919876543210', // Add phone number
  };

  final lat = _currentPosition?.latitude ?? 0.0;
  final lng = _currentPosition?.longitude ?? 0.0;

  _socketService.updateDriverStatus(
    driverId,
    isOnline,
    lat,
    lng,
    widget.vehicleType,
    fcmToken: driverFcmToken,
    profileData: driverProfileData, // This ensures profile is sent to server
  );

  print('📤 Driver profile sent: $driverProfileData');
}
  Widget buildEarningsCard() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: const [
        Text(
          "Today's Earnings",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        Text("₹0", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget buildPerformanceCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.green[100],
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Best Performance!",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "17/20 Completed Orders",
                  style: TextStyle(fontSize: 16),
                ),
                TextButton(
                  onPressed: () {},
                  child: Row(
                    children: const [
                      Text("Know more"),
                      Icon(Icons.arrow_forward),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const CircleAvatar(
            radius: 30,
            backgroundImage: AssetImage('assets/driver.jpg'),
          ),
        ],
      ),
    );
  }
}
