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
  void connect(
    String driverId,
    double lat,
    double lng, {
    String? vehicleType,
    bool isOnline = true,
    String? fcmToken,
  }) {
    _driverId = driverId;
    _vehicleType = vehicleType;
    _isOnline = isOnline;
    _fcmToken = fcmToken;
    _lastLat = lat;
    _lastLng = lng;

    socket = IO.io(
      'http://192.168.1.16:5002',
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
      print('🟢 Driver socket connected: ${socket.id}');
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

  // ====== MANUAL DRIVER STATUS UPDATE ======
  void updateDriverStatus(
    String driverId,
    bool isOnline,
    double lat,
    double lng,
    String vehicleType, {
    String? fcmToken,
    bool acceptsShort = false,
    bool acceptsParcel = false,
    bool acceptsLong = false,
  }) {
    if (!_isConnected) {
      print('⚠️ Socket not connected, cannot update driver status');
      return;
    }
    _driverId = driverId;
    _isOnline = isOnline;
    _lastLat = lat;
    _lastLng = lng;
    _vehicleType = vehicleType;
    _fcmToken = fcmToken;

    _emitDriverStatus(
      driverId,
      isOnline,
      lat,
      lng,
      vehicleType,
      fcmToken: fcmToken,
      acceptsShort: acceptsShort,
      acceptsParcel: acceptsParcel,
      acceptsLong: acceptsLong,
    );
  }

  void _emitDriverStatus(
    String driverId,
    bool isOnline,
    double lat,
    double lng,
    String vehicleType, {
    String? fcmToken,
    bool acceptsShort = false,
    bool acceptsParcel = false,
    bool acceptsLong = false,
  }) {
    final payload = {
      'driverId': driverId,
      'isOnline': isOnline,
      'vehicleType': vehicleType,
      'fcmToken': fcmToken,
      'acceptsShort': acceptsShort,
      'acceptsParcel': acceptsParcel,
      'acceptsLong': acceptsLong,
      'location': {
        'type': 'Point',
        'coordinates': [lng, lat],
      },
    };
    print('📤 Emitting updateDriverStatus: $payload');
    socket.emit('updateDriverStatus', payload);
  }

  // ====== ACCEPT RIDE ======
  void acceptRide(String driverId, Map<String, dynamic> rideData) {
    if (!_isConnected) {
      print('⚠️ Socket not connected, cannot accept ride');
      return;
    }
    final payload = {'tripId': rideData['tripId'], 'driverId': driverId};
    print('📤 Emitting driver:accept_trip with payload: $payload');
    socket.emit('driver:accept_trip', payload);
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

  // ====== DISCONNECT ======
  void disconnect() {
    print('🔄 Disconnecting socket manually');
    socket.disconnect();
    _stopLocationUpdates();
    _isConnected = false;
    print('🔴 Socket disconnected manually');
  }

  void dispose() {
    disconnect();
  }
}
