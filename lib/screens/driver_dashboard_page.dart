import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';

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
  final String apiBase = 'http://192.168.43.236:5002';

  bool isOnDuty = false;
  bool hasNewRide = false;
  String? ridePickup;
  String? rideDrop;
  GoogleMapController? _googleMapController;
  late String driverId;

  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  LatLng? _customerPickup;
  Timer? _locationUpdateTimer;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _requestLocationPermission();
    _getCurrentLocation();
    driverId = widget.driverId;
  }

  Future<void> _initializeFirebase() async {
    await Firebase.initializeApp();
    _initFirebaseMessaging();
  }

  Future<void> _initFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.subscribeToTopic("drivers");
    print("📢 Subscribed to 'drivers' topic");

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final pickup = message.data['pickup'] ?? 'Unknown Pickup';
      final drop = message.data['drop'] ?? 'Unknown Drop';

      setState(() {
        ridePickup = pickup;
        rideDrop = drop;
        hasNewRide = true;
      });
      _playNotificationSound(); // 🔔 Added
    });
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

  void acceptRide() {
    _stopNotificationSound();
    setState(() => hasNewRide = false);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Ride Accepted!")));

    // 🚀 Start sending live location updates every 5 seconds
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(Duration(seconds: 5), (_) async {
      final position = await Geolocator.getCurrentPosition();
      _sendLocationToBackend(position.latitude, position.longitude);
    });
  }

  void _startLiveLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (
      _,
    ) async {
      final pos = await Geolocator.getCurrentPosition();
      _sendLocationToBackend(pos.latitude, pos.longitude);
    });
  }

  Future<void> _sendLocationToBackend(double lat, double lng) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBase/api/location/updateDriver'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driverId': driverId, // ✅ NOT null or empty

          'latitude': lat, // ✅ Fix this
          'longitude': lng,
          'type': 'customer', // <-- REQUIRED!
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
        Uri.parse(
          'http://192.168.43.236:5002/api/location/customer/$customerId',
        ),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final double lat = data['latitude'];
        final double lng = data['longitude'];

        final pickupLatLng = LatLng(lat, lng);

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
        });

        // Move map camera to pickup location
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

    final response = await http.get(url);
    if (response.statusCode != 200) return;

    final data = jsonDecode(response.body);
    final encodedPolyline = data['routes'][0]['overview_polyline']['points'];
    final polylinePoints = _decodePolyline(encodedPolyline);

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
    super.dispose();
  }

  void rejectRide() {
    _locationUpdateTimer?.cancel(); // ⛔ Stop updates on rejection
    _stopNotificationSound(); // 🔔 Added
    setState(() => hasNewRide = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Ride Rejected.")));
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
              onChanged: (value) => setState(() => isOnDuty = value),
              activeColor: Colors.green,
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
          if (hasNewRide) buildRideRequestCard(),

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
                          Uri.parse(
                            "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving",
                          ),
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
                ],
              ),
              const SizedBox(height: 10),
              Text("Pickup: $ridePickup", style: const TextStyle(fontSize: 16)),
              Text("Drop: $rideDrop", style: const TextStyle(fontSize: 16)),
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
