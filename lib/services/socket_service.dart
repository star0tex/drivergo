import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class DriverSocketService {
  static final DriverSocketService _instance = DriverSocketService._internal();
  factory DriverSocketService() => _instance;
  DriverSocketService._internal();

  late IO.Socket socket;
  bool _isConnected = false;
  String? _vehicleType;

  Timer? _locationTimer;
  double? _lastLat;
  double? _lastLng;
  String? _driverId;
  bool _isOnline = true;
  String? _fcmToken;

  // ====== EVENT CALLBACKS ======
  Function(Map<String, dynamic>)? onRideRequest;
  Function(Map<String, dynamic>)? onRideConfirmed;
  Function(Map<String, dynamic>)? onRideCancelled;

  // ====== CONNECT SOCKET ======
 void connect(String driverId, double lat, double lng, {
  required String vehicleType, 
  required bool isOnline,
  String? fcmToken
}) {
    _driverId = driverId;
    _vehicleType = vehicleType;
    _isOnline = isOnline;
    _fcmToken = fcmToken;
    _lastLat = lat;
    _lastLng = lng;

    socket = IO.io(
      'http://192.168.1.9:5002',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .build(),
    );

    // On connect
    socket.onConnect((_) {
      print("✅ Connected to socket: ${socket.id}");
      _isConnected = true;

      // Use consistent payload format with capabilities
      _emitDriverStatus(
        driverId,
        isOnline,
        lat,
        lng,
        vehicleType,
        fcmToken: fcmToken,
      );

      _startLocationUpdates();
    });

    // On disconnect
    socket.onDisconnect((_) {
      print('🔴 Socket disconnected');
      _isConnected = false;
      _stopLocationUpdates();
    });

    // On reconnect
    socket.onReconnect((_) {
      print('🔄 Socket reconnected: ${socket.id}');
      _isConnected = true;

      _emitDriverStatus(
        _driverId!,
        _isOnline,
        _lastLat!,
        _lastLng!,
        _vehicleType ?? '',
        fcmToken: _fcmToken,
      );

      _startLocationUpdates();
    });

    // Add status confirmation listener
    socket.on('driver:statusUpdated', (data) {
      print('✅ Server confirmed driver status: $data');
    });

    // Trip request listeners
    socket.on('trip:request', (data) => _handleTripRequest(data));
    socket.on('shortTripRequest', (data) => _handleTripRequest(data));
    socket.on('parcelTripRequest', (data) => _handleTripRequest(data));
    socket.on('longTripRequest', (data) => _handleTripRequest(data));

    // Trip lifecycle events
    socket.on('rideConfirmed', (data) {
      print('✅ Ride confirmed: $data');
      if (onRideConfirmed != null) {
        onRideConfirmed!(Map<String, dynamic>.from(data));
      }
    });

    socket.on('rideCancelled', (data) {
      print('🚫 Ride cancelled: $data');
      if (onRideCancelled != null) {
        onRideCancelled!(Map<String, dynamic>.from(data));
      }
    });

    // ====== CUSTOMER LIVE LOCATION ======
    socket.on('location:update_customer', (data) {
      print("📍 Customer live location: $data");
    });

    // Remove duplicate emission at the end of connect method
  }

  // ====== AUTO LOCATION UPDATES ======
  void _startLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_driverId != null && _lastLat != null && _lastLng != null) {
        _emitDriverStatus(
          _driverId!,
          _isOnline,
          _lastLat!,
          _lastLng!,
          _vehicleType ?? '',
          fcmToken: _fcmToken,
        );
      }
    });
    print('📡 Started auto location updates every 10s');
  }

  void _stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
    print('🛑 Stopped auto location updates');
  }

  Map<String, bool> _getCapabilities(String vehicleType) {
    switch (vehicleType.toLowerCase()) {
      case "bike":
        return {
          'acceptsShort': true,
          'acceptsParcel': true,
          'acceptsLong': false,
        };
      case "car":
        return {
          'acceptsShort': true,
          'acceptsParcel': false,
          'acceptsLong': true,
        };
      case "auto":
        return {
          'acceptsShort': true,
          'acceptsParcel': false,
          'acceptsLong': false,
        };
      default:
        return {
          'acceptsShort': false,
          'acceptsParcel': false,
          'acceptsLong': false,
        };
    }
  }

  // ====== MANUAL DRIVER STATUS UPDATE ======
  void updateDriverStatus(
    String driverId,
    bool isOnline,
    double lat,
    double lng,
    String vehicleType, {
    String? fcmToken,
    Map<String, dynamic>? profileData,
  }) {
    if (!_isConnected) {
      print('⚠️ Socket not connected, cannot update driver status');
      return;
    }
    
    // Update internal state
    _isOnline = isOnline;
    _lastLat = lat;
    _lastLng = lng;
    
    // Use the same consistent method for emitting status
    _emitDriverStatus(
      driverId,
      isOnline,
      lat,
      lng,
      vehicleType,
      fcmToken: fcmToken,
      profileData: profileData,
    );
  }

  void _emitDriverStatus(
    String driverId,
    bool isOnline,
    double lat,
    double lng,
    String vehicleType, {
    String? fcmToken,
    Map<String, dynamic>? profileData,
    bool acceptsShort = false,
    bool acceptsParcel = false,
    bool acceptsLong = false,
  }) {
    final caps = _getCapabilities(vehicleType);

    final payload = {
      'driverId': driverId,
      'isOnline': isOnline,
      'vehicleType': vehicleType,
      'fcmToken': fcmToken,
      'acceptsShort': caps['acceptsShort'],
      'acceptsParcel': caps['acceptsParcel'],
      'acceptsLong': caps['acceptsLong'],
      'location': {
        'type': 'Point',
        'coordinates': [lng, lat],
      },
      if (profileData != null) 'profileData': profileData,
    };

    // Remove null values
    payload.removeWhere((key, value) => value == null);
    
    print('📤 Emitting updateDriverStatus - Online: $isOnline');
    socket.emit('updateDriverStatus', payload);
  }

  // ====== ACCEPT RIDE ======
  void acceptRide(String driverId, Map<String, dynamic> rideData) {
    final tripId = rideData['tripId'] ?? rideData['_id'];
    if (tripId == null) {
      print('❌ No tripId found in rideData: $rideData');
      return;
    }

    print('📤 [DriverSocketService] Accepting trip: $tripId');
    
    socket.emit('driver:accept_trip', {
      'tripId': tripId.toString(),
      'driverId': driverId,
    });
  }

  // ====== REJECT RIDE ======
  Future<void> rejectRide(String driverId, String rideId) async {
    print('🚫 Placeholder: Call backend /api/trip/reject for rideId: $rideId');
  }

  // ====== COMPLETE RIDE ======
  Future<void> completeRide(String driverId, String rideId) async {
    print('✅ Placeholder: Call backend /api/trip/complete for rideId: $rideId');
  }

  // ====== HANDLE TRIP REQUESTS ======
  void _handleTripRequest(dynamic data) {
    print('📩 Trip request: $data');
    if (onRideRequest != null) {
      onRideRequest!(Map<String, dynamic>.from(data));
    }
  }

  // ====== GET CURRENT STATUS ======
  bool get isOnline => _isOnline;
  bool get isConnected => _isConnected;

  // ====== UPDATE LOCATION ONLY ======
  void updateLocation(double lat, double lng) {
    _lastLat = lat;
    _lastLng = lng;
    
    if (_isConnected && _driverId != null && _vehicleType != null) {
      _emitDriverStatus(
        _driverId!,
        _isOnline,
        lat,
        lng,
        _vehicleType!,
        fcmToken: _fcmToken,
      );
    }
  }

  // ====== DISCONNECT ======
  void disconnect() {
    print('🔄 Disconnecting socket manually');
    
    // Send offline status before disconnecting
    if (_isConnected && _driverId != null && _lastLat != null && _lastLng != null) {
      _emitDriverStatus(
        _driverId!,
        false, // Set to offline
        _lastLat!,
        _lastLng!,
        _vehicleType ?? '',
        fcmToken: _fcmToken,
      );
    }
    
    socket.disconnect();
    _stopLocationUpdates();
    _isConnected = false;
    _isOnline = false;
    print('🔴 Socket disconnected manually');
  }

  void dispose() {
    disconnect();
  }
}