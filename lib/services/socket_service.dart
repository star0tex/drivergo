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
      'https://cd4ec7060b0b.ngrok-free.app',
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
  void on(String event, Function(dynamic) handler) {
    if (_isConnected) {
      socket.on(event, handler);
    }
  }

  /// Generic method to stop listening to an event
  void off(String event) {
    if (_isConnected) {
      socket.off(event);
    }
  }

  /// Generic method to emit an event
  void emit(String event, dynamic data) {
    if (_isConnected) {
      socket.emit(event, data);
    }
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
  // ====== NEW: GO TO PICKUP ======
Future<void> goToPickup(String driverId, String tripId) async {
  print('🚗 Going to pickup for trip: $tripId');
  socket.emit('driver:going_to_pickup', {
    'tripId': tripId,
    'driverId': driverId,
  });
}

// ====== NEW: START RIDE WITH OTP ======
Future<void> startRideWithOTP(
  String driverId, 
  String tripId, 
  String otp,
  double driverLat,
  double driverLng,
) async {
  print('▶️ Starting ride with OTP for trip: $tripId');
  socket.emit('driver:start_ride', {
    'tripId': tripId,
    'driverId': driverId,
    'otp': otp,
    'driverLat': driverLat,
    'driverLng': driverLng,
  });
}

// ====== NEW: COMPLETE RIDE WITH VERIFICATION ======
Future<void> completeRideWithVerification(
  String driverId,
  String tripId,
  double driverLat,
  double driverLng,
) async {
  print('🏁 Completing ride with verification for trip: $tripId');
  socket.emit('driver:complete_ride', {
    'tripId': tripId,
    'driverId': driverId,
    'driverLat': driverLat,
    'driverLng': driverLng,
  });
}

// ====== NEW: CONFIRM CASH COLLECTION ======
Future<void> confirmCashCollection(String driverId, String tripId) async {
  print('💰 Confirming cash collection for trip: $tripId');
  socket.emit('driver:confirm_cash', {
    'tripId': tripId,
    'driverId': driverId,
  });
}

// ====== SEND DRIVER LOCATION FOR LIVE TRACKING ======
void sendDriverLocation(String tripId, double lat, double lng) {
  if (_isConnected) {
    socket.emit('driver:location', {
      'tripId': tripId,
      'latitude': lat,
      'longitude': lng,
    });
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