import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
//import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:drivergoo/services/socket_service.dart';

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
  final String apiBase = 'http://192.168.190.33:5002';

  bool isOnDuty = false;
  List<Map<String, dynamic>> rideRequests = []; // Queue of ride requests
  Map<String, dynamic>? currentRide; // Currently displayed request

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
    _connectSocket();
    _requestLocationPermission();
    _getCurrentLocation();

    // By default, driver is offline initially
    _registerDriver(false);
  }

  Future<void> _registerDriver(bool isOnline) async {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // Send HTTP request to update driver status in backend database
    try {
      final response = await http.post(
        Uri.parse('$apiBase/api/driver/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driverId': driverId,
          'isOnline': isOnline,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'vehicleType': widget.vehicleType
        }),
      );
      
      if (response.statusCode == 200) {
        print("✅ Driver status updated in backend: ${isOnline ? 'Online' : 'Offline'}");
      } else {
        print("❌ Failed to update driver status: ${response.statusCode}, ${response.body}");
      }
    } catch (e) {
      print("❌ Error updating driver status: $e");
    }
    
    if (isOnline) {
      // If driver is going online, ensure socket is connected first
      _ensureSocketConnection();
      
      // Explicitly update driver status via socket service
      _socketService.updateDriverStatus(
        driverId,
        isOnline,
        pos.latitude,
        pos.longitude,
        widget.vehicleType
      );
    } else {
      // If going offline, first update status then disconnect socket
      _socketService.updateDriverStatus(
        driverId,
        isOnline,
        pos.latitude,
        pos.longitude,
        widget.vehicleType
      );
      
      // Disconnect after sending offline status
      _socketService.disconnect();
    }

    // Use the socket service to update driver location
    _socketService.updateDriverLocation(
      driverId,
      pos.latitude,
      pos.longitude,
    );
    
    print("📡 Driver status sent: ${isOnline ? 'Online' : 'Offline'}");
  }
  
  void _ensureSocketConnection() {
    print("🔄 Ensuring socket connection with status: ${isOnDuty ? 'Online' : 'Offline'}");
    // Get current position and reconnect socket if needed
    Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high).then((position) {
      print("📍 Got position for socket connection: ${position.latitude}, ${position.longitude}");
      _socketService.connect(
        driverId,
        position.latitude,
        position.longitude,
        vehicleType: widget.vehicleType,
        isOnline: isOnDuty,
      );
      
      // Set up the ride request callback
      _socketService.onRideRequest = _handleIncomingTrip;
      
      // Send additional vehicle type information to backend
      try {
        http.post(
          Uri.parse('$apiBase/api/driver/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'driverId': driverId,
            'lat': position.latitude,
            'lng': position.longitude,
            'vehicleType': widget.vehicleType,
            'isOnline': true
          }),
        ).then((response) {
          if (response.statusCode == 200) {
            print("✅ Driver registered with vehicle type: ${widget.vehicleType}");
          } else {
            print("❌ Failed to register driver: ${response.statusCode}, ${response.body}");
          }
        });
      } catch (e) {
        print("❌ Error registering driver: $e");
      }
      
      print("✅ Socket connection ensured");
    });
  }

  void _connectSocket() async {
    // Get current location
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    
    // Connect using the DriverSocketService
    _socketService.connect(
      driverId,
      pos.latitude,
      pos.longitude,
      vehicleType: widget.vehicleType,
      isOnline: isOnDuty, // Pass the current duty status
    );
    
    // Set up the ride request callback
    _socketService.onRideRequest = _handleIncomingTrip;
    
    print("✅ Connected to socket server");
    print("📡 Driver registered with location: ${pos.latitude}, ${pos.longitude}");
    print("📡 Driver status: ${isOnDuty ? 'Online' : 'Offline'}");
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

  void _playNotificationSound() async {
    // 🔔 Added
    await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
  }

  void _stopNotificationSound() async {
    // 🔔 Added
    await _audioPlayer.stop();
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
      Uri.parse('http://192.168.190.33:5002/api/driver/login'),
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
      currentRide!,
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
      _socketService.updateDriverLocation(
        driverId,
        pos.latitude,
        pos.longitude,
      );

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
                await _registerDriver(isOnDuty);
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
