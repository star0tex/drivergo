import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:drivergoo/services/socket_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';


class DriverDashboardPage extends StatefulWidget {
  final String driverId;
  final String vehicleType;

  const DriverDashboardPage({
    super.key,
    required this.driverId,
    required this.vehicleType,
  });
  @override
  State<DriverDashboardPage> createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends State<DriverDashboardPage> {
  
    io.Socket? socket;

  final String apiBase = 'http://192.168.1.16:5002';


  bool isOnDuty = false;
  List<Map<String, dynamic>> rideRequests = []; // Queue of ride requests
  Map<String, dynamic>? currentRide; // Currently displayed request
  Map<String, dynamic>? confirmedRide; // Currently confirmed ride

  GoogleMapController? _googleMapController;
  late String driverId;

  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  LatLng? _customerPickup;
  Timer? _locationUpdateTimer;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  final DriverSocketService _socketService = DriverSocketService();
  @override
void initState() {
  super.initState();
  driverId = widget.driverId;

  // ✅ Ensure only one socket connection
  _initDriverSocket();
    _requestLocationPermission();
    _getCurrentLocation();
  _requestLocationPermission();
  _getCurrentLocation();

  // Initially driver offline, will be set online after socket connects
}
 Future<void> _initDriverSocket() async {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // Connect using singleton socket service
    _socketService.connect(
      driverId,
      pos.latitude,
      pos.longitude,
      vehicleType: widget.vehicleType,
      isOnline: isOnDuty,
    );

    // Listen for socket connection
    _socketService.socket.onConnect((_) async {
      print("✅ Socket connected: ${_socketService.socket.id}");
      print("📍 Current location: ${pos.latitude}, ${pos.longitude}");

      // Send driver status after socket connects
      _socketService.updateDriverStatus(
        driverId,
        isOnDuty,
        pos.latitude,
        pos.longitude,
        widget.vehicleType,
      );

      // Update location as well
      _socketService.updateDriverLocation(
        driverId,
        pos.latitude,
        pos.longitude,
      );

      print("📡 Driver is now Online and location sent");
    });

    _socketService.socket.onDisconnect((_) {
      print("🔴 Socket disconnected");
    });

    _socketService.socket.onReconnect((_) {
      print("🔄 Socket reconnected: ${_socketService.socket.id}");

      // Re-send status/location on reconnect
      _socketService.updateDriverStatus(
        driverId,
        isOnDuty,
        pos.latitude,
        pos.longitude,
        widget.vehicleType,
      );
      _socketService.updateDriverLocation(
        driverId,
        pos.latitude,
        pos.longitude,
      );
    });

    // Set up ride request callback
    _socketService.onRideRequest = _handleIncomingTrip;

    // Set up ride confirmed callback
    _socketService.onRideConfirmed = _handleRideConfirmation;
  }



 
  
  

  void _handleIncomingTrip(dynamic data) {
    print("📥 Incoming trip: $data"); // Log to see what the backend sends

    // First check if driver is on duty
    if (!isOnDuty) {
      print("❌ Ignored because driver is off duty");
      return;
    }
    
    final request = Map<String, dynamic>.from(data);
    
    // Compare vehicle types case-insensitively
    String requestVehicleType = request['vehicleType']?.toString().toLowerCase() ?? '';
    String driverVehicleType = widget.vehicleType.toLowerCase();
    
    if (requestVehicleType != driverVehicleType) {
      print("🚫 Vehicle type mismatch. Expected: $driverVehicleType, Got: $requestVehicleType");
      return;
    }

    // Process the ride request
    setState(() {
      rideRequests.add(request);
      currentRide = rideRequests.isNotEmpty ? rideRequests.first : null;
    });
    _playNotificationSound();
  }
  
  void _handleRideConfirmation(dynamic data) {
    print("✅ Ride confirmation received: $data");
    
    // First check if driver is on duty
    if (!isOnDuty) {
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
        content: Text('Ride confirmed! ${confirmation['message'] ?? 'Customer has confirmed the ride.'}'),
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
        title: const Text('Ride Confirmed', style: TextStyle(color: Colors.green)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ride ID: ${confirmation['rideId'] ?? confirmation['id'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Customer: ${confirmation['userName'] ?? confirmation['customerName'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Pickup: ${_getAddressFromConfirmation(confirmation, 'pickup')}'),
              const SizedBox(height: 8),
              Text('Destination: ${_getAddressFromConfirmation(confirmation, 'drop')}'),
              const SizedBox(height: 8),
              Text('Payment: ${confirmation['paymentMethod'] ?? 'Cash'}'),
              const SizedBox(height: 8),
              Text('Amount: ₹${confirmation['fare'] ?? confirmation['amount'] ?? 'N/A'}'),
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
  
  String _getAddressFromConfirmation(Map<String, dynamic> confirmation, String type) {
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
        pickupLat = double.tryParse(confirmation['pickup']['lat']?.toString() ?? '') ?? 
                   double.tryParse(confirmation['pickup']['latitude']?.toString() ?? '');
        pickupLng = double.tryParse(confirmation['pickup']['lng']?.toString() ?? '') ?? 
                   double.tryParse(confirmation['pickup']['longitude']?.toString() ?? '');
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
        print('❌ Could not extract pickup location from confirmation: $confirmation');
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to complete ride')),
      );
    }
  }
  
  void _cancelRide(Map<String, dynamic> confirmation) {
    try {
      // Clear the confirmed ride from state
      _clearConfirmedRide();
      
      // Clear the route and markers
      _clearRouteAndMarkers();
      
      // Show message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride cancelled')),
      );
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
      Uri.parse('http://192.168.1.16:5002/api/driver/login'),
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
    
    // Use the socket service to accept the ride
    _socketService.acceptRide(
      driverId,
      currentRide!['userId'] ?? currentRide!['customerId'],
    );

    await _fetchCustomerPickupLocation(currentRide!['userId'] ?? currentRide!['customerId']);
    await _drawRouteToCustomer();
    _startLiveLocationUpdates();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Ride Accepted!")));

    setState(() {
      currentRide = rideRequests.isNotEmpty ? rideRequests.removeAt(0) : null;
      if (currentRide != null) _playNotificationSound();
    });
  }

  void _startLiveLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (
      _,
    ) async {
      if (currentRide == null) return;
      final pos = await Geolocator.getCurrentPosition();

      // Use the socket service to update driver location
     _socketService.updateDriverStatus(driverId, true, pos.latitude, pos.longitude, widget.vehicleType);


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
          'type': 'driver', // Changed from 'customer' to 'driver'
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
    _locationUpdateTimer?.cancel();
    _mapController?.dispose();
    _socketService.disconnect(); // Disconnect the socket service
    _stopNotificationSound();
      socket?.disconnect();
    
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
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Row(
          children: [
            Text(
              isOnDuty ? "ON DUTY" : "OFF DUTY",
              style: const TextStyle(color: Colors.black),
            ),
            Switch(
              value: isOnDuty,
              activeColor: Colors.green,
              inactiveThumbColor: Colors.red,
              onChanged: (value) async {
                print("🔄 Toggle switch changed to: ${value ? 'Online' : 'Offline'}");
                setState(() => isOnDuty = value);
                print("✅ _registerDriver completed with status: ${isOnDuty ? 'Online' : 'Offline'}");
              },
            ),
          ],
        ),
        actions: const [
          Icon(Icons.location_on_outlined, color: Colors.black),
          SizedBox(width: 10),
          Icon(Icons.notifications_none, color: Colors.black),
          SizedBox(width: 10),
        ],
      ),

      body: Stack(
        children: [
          // Show map or off-duty UI
          isOnDuty ? buildGoogleMap() : buildOffDutyUI(),
          
          // Show confirmed ride banner if available
          if (confirmedRide != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.green.withOpacity(0.9),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ride confirmed: ${_getAddressFromConfirmation(confirmedRide!, "pickup")}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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

          // Show ride request card if available
          if (currentRide != null) buildRideRequestCard(),

          // Show bottom sheet with "Go to Pickup" if pickup location is set
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
                    const Text(
                      "Navigate to Customer Pickup Location",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
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
                      child: const Text("Go to Pickup"),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildRideRequestCard() {
    if (currentRide == null) return const SizedBox();

    return Align(
      alignment: Alignment.bottomCenter,
      child: Card(
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.directions_bike, color: Colors.indigo),
                  const SizedBox(width: 8),
                  const Text(
                    "New Ride Request",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  // Ride request count badge
                  if (rideRequests.isNotEmpty)
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.red,
                      child: Text(
                        "${rideRequests.length + 1}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                "Pickup: ${currentRide!['pickup']['address'] ?? ''}",
                style: const TextStyle(fontSize: 16),
              ),
              Text(
                "Drop: ${currentRide!['drop']['address'] ?? ''}",
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                    onPressed: rejectRide,
                    child: const Text("Reject"),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
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

  Widget buildGoogleMap() {
    return GoogleMap(
      onMapCreated: (controller) => _googleMapController = controller,
      initialCameraPosition: CameraPosition(
        target: _currentPosition ?? const LatLng(0, 0),
        zoom: 14,
      ),
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      markers: _markers,
      polylines: _polylines,
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
        const Center(child: Text("Start the engine, chase the earnings!")),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            "Go ON DUTY to start earning",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
            decoration: const BoxDecoration(color: Colors.white),
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
                    Text("My Profile", style: TextStyle(fontSize: 18)),
                    Text("-- ⭐", style: TextStyle(fontSize: 14)),
                  ],
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                  child: const Text("Best"),
                ),
              ],
            ),
          ),
          buildDrawerItem(
            Icons.account_balance_wallet,
            "Earnings",
            "Transfer Money to Bank, History",
          ),
          buildDrawerItem(
            Icons.attach_money,
            "Incentives and More",
            "Know how you get paid",
          ),
          buildDrawerItem(
            Icons.card_giftcard,
            "Rewards",
            "Insurance and Discounts",
          ),
          const Divider(),
          buildDrawerItem(
            Icons.view_module,
            "Service Manager",
            "Food Delivery & more",
          ),
          buildDrawerItem(
            Icons.map,
            "Demand Planner",
            "Past High Demand Areas",
          ),
          buildDrawerItem(
            Icons.headset_mic,
            "Help",
            "Support, Accident Insurance",
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFEFF5FF),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.emoji_people, color: Colors.green),
                  const SizedBox(width: 8),
                  const Expanded(child: Text("Refer friends & Earn up to ₹")),
                  TextButton(onPressed: () {}, child: const Text("Refer Now")),
                ],
              ),
            ),
          ),
          ListTile(
            title: const Text("On-Ride Booking"),
            trailing: Switch(
              value: isOnDuty,
              onChanged: (value) => setState(() => isOnDuty = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDrawerItem(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () {},
    );
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
