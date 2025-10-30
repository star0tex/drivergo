// socket_service.dart - FULLY COMPATIBLE VERSION

import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';

class DriverSocketService {
  static final DriverSocketService _instance = DriverSocketService._internal();
  factory DriverSocketService() => _instance;
  DriverSocketService._internal();

  // ✅ Keep non-nullable for backward compatibility with existing code
  late IO.Socket socket;
  bool _isConnected = false;
  String? _vehicleType;

  Timer? _locationTimer;
  Timer? _reconnectTimer;
  double? _lastLat;
  double? _lastLng;
  String? _driverId;
  bool _isOnline = true;
  String? _fcmToken;
  
  // Track active trip to prevent disconnection
  String? _activeTripId;
  bool _hasActiveTrip = false;

  // Event callbacks
  Function(Map<String, dynamic>)? onRideRequest;
  Function(Map<String, dynamic>)? onRideConfirmed;
  Function(Map<String, dynamic>)? onRideCancelled;

  // Set active trip (prevents disconnection)
  void setActiveTrip(String? tripId) {
    _activeTripId = tripId;
    _hasActiveTrip = tripId != null;
    
    if (_hasActiveTrip) {
      print('🔒 Active trip set: $tripId - Socket will persist');
      _saveActiveTripToPrefs(tripId!);
    } else {
      print('🔓 No active trip - Normal socket behavior');
      _clearActiveTripFromPrefs();
    }
  }

  // Save active trip to SharedPreferences
  Future<void> _saveActiveTripToPrefs(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeTripId', tripId);
    await prefs.setBool('hasActiveTrip', true);
  }

  // Clear active trip from SharedPreferences
  Future<void> _clearActiveTripFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('activeTripId');
    await prefs.setBool('hasActiveTrip', false);
  }

  // Check for active trip on app restart
  Future<bool> hasActiveTripOnRestart() async {
    final prefs = await SharedPreferences.getInstance();
    _activeTripId = prefs.getString('activeTripId');
    _hasActiveTrip = prefs.getBool('hasActiveTrip') ?? false;
    
    if (_hasActiveTrip && _activeTripId != null) {
      print('⚠️ Found active trip on restart: $_activeTripId');
      return true;
    }
    return false;
  }

 void connect(String driverId, double lat, double lng, {
  required String vehicleType, 
  required bool isOnline,
  String? fcmToken
}) {
  // ✅ Check if already connected
  try {
    if (socket.connected) {
      print('🔌 Socket already connected: ${socket.id}');
      
      // ✅ IMPORTANT: Still update status even if connected
      _emitDriverStatus(driverId, isOnline, lat, lng, vehicleType, fcmToken: fcmToken);
      return;
    }
  } catch (e) {
    print('🔡 Initializing new socket connection...');
  }

  _driverId = driverId;
  _vehicleType = vehicleType;
  _isOnline = isOnline;
  _fcmToken = fcmToken;
  _lastLat = lat;
  _lastLng = lng;

  print('');
  print('=' * 70);
  print('🔌 CREATING NEW SOCKET');
  print('   Driver ID: $driverId');
  print('   Vehicle Type: $vehicleType');
  print('   Online: $isOnline');
  print('   FCM Token: ${fcmToken ?? "NONE"}'); // ✅ LOG THIS
  print('   Location: $lat, $lng');
  print('=' * 70);
  print('');

  socket = IO.io(
    'https://b23b44ae0c5e.ngrok-free.app',
    IO.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .setQuery({'driverId': driverId})
        .enableReconnection()
        .setReconnectionAttempts(999999)
        .setReconnectionDelay(2000)
        .setReconnectionDelayMax(10000)
        .build(),
  );

  // On connect
  socket.onConnect((_) {
    print('');
    print('=' * 70);
    print("✅ SOCKET CONNECTED");
    print('   Socket ID: ${socket.id}');
    print('   Driver ID: $driverId');
    print('=' * 70);
    print('');
    
    _isConnected = true;

    // ✅ CRITICAL: Emit status immediately on connect
    _emitDriverStatus(driverId, isOnline, lat, lng, vehicleType, fcmToken: fcmToken);
    
    _startLocationUpdates();
    _startReconnectMonitor();
  });

    // On disconnect
    socket.onDisconnect((_) {
      print('🔴 Socket disconnected');
      print('⚠️ Socket disconnected — will retry...');
      _isConnected = false;
      _stopLocationUpdates();
      
      // Auto-reconnect if there's an active trip
      if (_hasActiveTrip) {
        print('⚠️ CRITICAL: Disconnected during active trip! Reconnecting...');
        _attemptReconnect();
      } else {
        _reconnect(); // Standard reconnect for non-active trips
      }
    });

    // ✅ Error handling
    socket.onError((err) {
      print('❌ Socket error: $err');
      if (_hasActiveTrip) {
        print('⚠️ Error during active trip - attempting reconnect');
        _attemptReconnect();
      }
    });

    // On reconnect
    socket.onReconnect((_) {
      print('🔄 Socket reconnected: ${socket.id}');
      _isConnected = true;

      _emitDriverStatus(_driverId!, _isOnline, _lastLat!, _lastLng!, _vehicleType ?? '', fcmToken: _fcmToken);
      _startLocationUpdates();
      
      // If there was an active trip, notify server
      if (_hasActiveTrip && _activeTripId != null) {
        print('🔄 Resuming active trip: $_activeTripId');
      }
    });

    socket.on('driver:statusUpdated', (data) {
      print('✅ Server confirmed driver status: $data');
    });

    // Trip listeners
    socket.on('trip:request', (data) => _handleTripRequest(data));
    socket.on('shortTripRequest', (data) => _handleTripRequest(data));
    socket.on('parcelTripRequest', (data) => _handleTripRequest(data));
    socket.on('longTripRequest', (data) => _handleTripRequest(data));

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

    socket.on('location:update_customer', (data) {
      print("📍 Customer live location: $data");
    });

    // ✅ Explicitly connect
      print('🔌 Calling socket.connect()...');

    socket.connect();
  }

  // ✅ Standard reconnect with delay
  void _reconnect() {
    Future.delayed(const Duration(seconds: 5), () {
      try {
        if (!socket.connected) {
          print('🔄 Attempting socket reconnect...');
          socket.connect();
        }
      } catch (e) {
        print('⚠️ Reconnect error: $e');
      }
    });
  }

  // Monitor connection health and force reconnect if needed
  void _startReconnectMonitor() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isConnected && _hasActiveTrip) {
        print('⚠️ Connection lost during active trip - forcing reconnect');
        _attemptReconnect();
      }
    });
  }

  // Force reconnection
  void _attemptReconnect() {
    try {
      if (!socket.connected) {
        print('🔄 Attempting manual reconnection...');
        socket.connect();
      }
    } catch (e) {
      print('⚠️ Manual reconnect error: $e');
    }
  }

  void on(String event, Function(dynamic) handler) {
    try {
      if (_isConnected && socket.connected) {
        socket.on(event, handler);
      }
    } catch (e) {
      print('⚠️ Error registering event listener for $event: $e');
    }
  }

  void off(String event) {
    try {
      if (_isConnected && socket.connected) {
        socket.off(event);
      }
    } catch (e) {
      print('⚠️ Error removing event listener for $event: $e');
    }
  }

  void emit(String event, dynamic data) {
    try {
      if (socket.connected) {
        socket.emit(event, data);
        print('📤 Emitted: $event');
      } else {
        print('⚠️ Cannot emit $event - socket disconnected');
        if (_hasActiveTrip) {
          print('🔄 Reconnecting to emit event...');
          _attemptReconnect();
          // Retry after 1 second
          Future.delayed(const Duration(seconds: 1), () {
            try {
              if (socket.connected) {
                socket.emit(event, data);
                print('📤 Emitted after reconnect: $event');
              }
            } catch (e) {
              print('❌ Failed to emit after reconnect: $e');
            }
          });
        }
      }
    } catch (e) {
      print('❌ Error emitting $event: $e');
    }
  }

  void _startLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_driverId != null && _lastLat != null && _lastLng != null) {
        _emitDriverStatus(_driverId!, _isOnline, _lastLat!, _lastLng!, _vehicleType ?? '', fcmToken: _fcmToken);
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
        return {'acceptsShort': true, 'acceptsParcel': true, 'acceptsLong': false};
      case "car":
        return {'acceptsShort': true, 'acceptsParcel': false, 'acceptsLong': true};
      case "auto":
        return {'acceptsShort': true, 'acceptsParcel': false, 'acceptsLong': false};
      default:
        return {'acceptsShort': false, 'acceptsParcel': false, 'acceptsLong': false};
    }
  }

  void updateDriverStatus(String driverId, bool isOnline, double lat, double lng, String vehicleType, {
    String? fcmToken,
    Map<String, dynamic>? profileData,
  }) {
    if (!_isConnected) {
      print('⚠️ Socket not connected, attempting reconnection...');
      if (_hasActiveTrip) {
        _attemptReconnect();
      }
      return;
    }
    
    _isOnline = isOnline;
    _lastLat = lat;
    _lastLng = lng;
    
    _emitDriverStatus(driverId, isOnline, lat, lng, vehicleType, fcmToken: fcmToken, profileData: profileData);
  }

  void _emitDriverStatus(String driverId, bool isOnline, double lat, double lng, String vehicleType, {
    String? fcmToken,
    Map<String, dynamic>? profileData,
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

    payload.removeWhere((key, value) => value == null);
    
    print('📤 Emitting updateDriverStatus - Online: $isOnline');
    emit('updateDriverStatus', payload);
  }

  void acceptRide(String driverId, Map<String, dynamic> rideData) {
    final tripId = rideData['tripId'] ?? rideData['_id'];
    if (tripId == null) {
      print('❌ No tripId found in rideData: $rideData');
      return;
    }

    print('📤 Accepting trip: $tripId');
    
    // Mark as active trip BEFORE accepting
    setActiveTrip(tripId.toString());
    
    emit('driver:accept_trip', {
      'tripId': tripId.toString(),
      'driverId': driverId,
    });
  }

  Future<void> rejectRide(String driverId, String rideId) async {
    print('🚫 Rejecting ride: $rideId');
  }

  Future<void> completeRide(String driverId, String rideId) async {
    print('✅ Completing ride: $rideId');
    // Clear active trip AFTER completion
    setActiveTrip(null);
  }

  void _handleTripRequest(dynamic data) {
    print('📩 Trip request: $data');
    if (onRideRequest != null) {
      onRideRequest!(Map<String, dynamic>.from(data));
    }
  }

  bool get isOnline => _isOnline;
  bool get isConnected => _isConnected;
  bool get hasActiveTrip => _hasActiveTrip;

  void updateLocation(double lat, double lng) {
    _lastLat = lat;
    _lastLng = lng;
    
    if (_isConnected && _driverId != null && _vehicleType != null) {
      _emitDriverStatus(_driverId!, _isOnline, lat, lng, _vehicleType!, fcmToken: _fcmToken);
    }
  }

  Future<void> goToPickup(String driverId, String tripId) async {
    print('🚗 Going to pickup for trip: $tripId');
    emit('driver:going_to_pickup', {
      'tripId': tripId,
      'driverId': driverId,
    });
  }

  Future<void> startRideWithOTP(String driverId, String tripId, String otp, double driverLat, double driverLng) async {
    print('▶️ Starting ride with OTP for trip: $tripId');
    emit('driver:start_ride', {
      'tripId': tripId,
      'driverId': driverId,
      'otp': otp,
      'driverLat': driverLat,
      'driverLng': driverLng,
    });
  }

  Future<void> completeRideWithVerification(String driverId, String tripId, double driverLat, double driverLng) async {
    print('🏁 Completing ride with verification for trip: $tripId');
    emit('driver:complete_ride', {
      'tripId': tripId,
      'driverId': driverId,
      'driverLat': driverLat,
      'driverLng': driverLng,
    });
  }

  Future<void> confirmCashCollection(String driverId, String tripId) async {
    print('💰 Confirming cash collection for trip: $tripId');
    emit('driver:confirm_cash', {
      'tripId': tripId,
      'driverId': driverId,
    });
    
    // Clear active trip AFTER cash collection
    setActiveTrip(null);
  }

  void sendDriverLocation(String tripId, double lat, double lng) {
    if (_isConnected) {
      emit('driver:location', {
        'tripId': tripId,
        'latitude': lat,
        'longitude': lng,
      });
    }
  }

  // Only disconnect if NO active trip
  void disconnect() {
    if (_hasActiveTrip) {
      print('⚠️ CANNOT DISCONNECT - Active trip in progress: $_activeTripId');
      print('💡 Driver must complete trip first!');
      return;
    }
    
    try {
      if (socket.connected) {
        print('🔌 Disconnecting socket...');
        print('🔄 Disconnecting socket manually');
        
        if (_isConnected && _driverId != null && _lastLat != null && _lastLng != null) {
          _emitDriverStatus(_driverId!, false, _lastLat!, _lastLng!, _vehicleType ?? '', fcmToken: _fcmToken);
        }
        
        socket.disconnect();
        _stopLocationUpdates();
        _reconnectTimer?.cancel();
        _isConnected = false;
        _isOnline = false;
        print('🔴 Socket disconnected manually');
      }
    } catch (e) {
      print('⚠️ Error during disconnect: $e');
    }
  }

  void dispose() {
    // Only dispose if no active trip
    if (!_hasActiveTrip) {
      disconnect();
    } else {
      print('⚠️ CANNOT DISPOSE - Active trip in progress');
    }
  }
}