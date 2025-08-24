import 'package:socket_io_client/socket_io_client.dart' as IO;

class DriverSocketService {
  static final DriverSocketService _instance = DriverSocketService._internal();
  factory DriverSocketService() => _instance;
  DriverSocketService._internal();

  late IO.Socket socket;

  bool _isConnected = false;
  String? _vehicleType;

  void connect(
    String driverId,
    double lat,
    double lng, {
    String? vehicleType,
    bool isOnline = true,
    String? fcmToken,
  }) {
    if (vehicleType != null) {
      _vehicleType = vehicleType;
    }

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

   socket.onConnect((_) {
  print('🟢 Driver socket connected');

  // ✅ register driver online
  socket.emit('registerDriver', {
    'driverId': driverId,
    'lat': lat,
    'lng': lng,
    'vehicleType': vehicleType,
    'isOnline': true, // must be true
    'fcmToken': fcmToken,
  });
});
   socket.onConnect((_) {
  print('✅ Socket connected: ${socket.id}');
      _isConnected = false;
    });

    socket.onDisconnect((_) {
      print('🔴 Socket disconnected');
      _isConnected = false;
    });
socket.onReconnect((_) {
  print('🔄 Socket reconnected: ${socket.id}');

      _isConnected = true;

      // re-register after reconnect
      socket.emit('registerDriver', {
        'driverId': driverId,
        'lat': lat,
        'lng': lng,
        'vehicleType': _vehicleType,
        'isOnline': isOnline,
        'fcmToken': fcmToken,
      });
    });

    // Listen to all possible trip request event types
    socket.on('newRideRequest', (data) {
      print('📩 New ride request: $data');
      if (onRideRequest != null) onRideRequest!(Map<String, dynamic>.from(data));
    });

    socket.on('trip:Request', (data) {
      print('📩 Trip request: $data');
      if (onRideRequest != null) onRideRequest!(Map<String, dynamic>.from(data));
    });

    socket.on('shortTripRequest', (data) {
      print('📩 Short trip request: $data');
      if (onRideRequest != null) onRideRequest!(Map<String, dynamic>.from(data));
    });

    socket.on('parcelTripRequest', (data) {
      print('📩 Parcel trip request: $data');
      if (onRideRequest != null) onRideRequest!(Map<String, dynamic>.from(data));
    });

    socket.on('longTripRequest', (data) {
  print('📩 Long trip request: $data');
  if (onRideRequest != null) onRideRequest!(Map<String, dynamic>.from(data));
});

    // Ride confirmed
    socket.on('rideConfirmed', (data) {
      print('✅ Ride confirmed: $data');
      if (onRideConfirmed != null) onRideConfirmed!(Map<String, dynamic>.from(data));
    });

    // Ride completed
    socket.on('rideCompleted', (data) {
      print('📥 Received ride completion confirmation: $data');
    });

    // Ride cancelled
    socket.on('rideCancelled', (data) {
      print('📥 Received ride cancellation: $data');
    });
  }
 void updateDriverLocation(String driverId, double lat, double lng) {
    if (socket != null && socket!.connected) {
      socket!.emit("updateDriverLocation", {
        "driverId": driverId,
        "lat": lat,
        "lng": lng,
      });
      print("📡 Location update sent: $lat, $lng");
    } else {
      print("⚠️ Socket not connected, cannot send location");
    }
  }

  void dispose() {
    socket?.disconnect();
  }

  void updateDriverStatus(
    String driverId,
    bool isOnline,
    double lat,
    double lng,
    String vehicleType, {
    String? fcmToken,
  }) {
    print('🔄 Attempting to update driver status via socket: ${isOnline ? "Online" : "Offline"}');

    if (!_isConnected) {
      print('⚠️ Socket not connected, cannot update driver status');
      return;
    }

    final payload = {
      'driverId': driverId,
      'isOnline': isOnline,
      'vehicleType': vehicleType,
      'fcmToken': fcmToken,
      'location': {
        'type': 'Point',
        'coordinates': [lng, lat], // ✅ GeoJSON order [lng, lat]
      },
    };

    print('📤 Emitting updateDriverStatus with payload: $payload');
    socket.emit('updateDriverStatus', payload);

    print('📡 Driver status updated via socket: ${isOnline ? "Online" : "Offline"}');
  }

  void acceptRide(String driverId, Map<String, dynamic> rideData) {
    if (!_isConnected) {
      print('⚠️ Socket not connected, cannot accept ride');
      return;
    }

    final payload = {
      'tripId': rideData['tripId'],
      'driverId': driverId,
    };

    print('📤 Emitting driver:accept_trip with payload: $payload');
    socket.emit('driver:accept_trip', payload);
  }

  void rejectRide(String driverId, String rideId) {
    if (!_isConnected) {
      print('⚠️ Socket not connected, cannot reject ride');
      return;
    }

    socket.emit('rideRejected', {'driverId': driverId, 'rideId': rideId});
  }

  void disconnect() {
    print('🔄 Disconnecting socket manually');
    socket.disconnect();
    _isConnected = false;
    print('🔴 Socket disconnected manually');
  }

  void completeRide(String driverId, String rideId) {
    if (!_isConnected) {
      print('⚠️ Socket not connected, cannot complete ride');
      return;
    }

    socket.emit('rideCompleted', {'driverId': driverId, 'rideId': rideId});
    print('📤 Emitted rideCompleted for ride: $rideId');
  }

  Function(Map<String, dynamic>)? onRideRequest;
  Function(Map<String, dynamic>)? onRideConfirmed;
}
