import 'package:socket_io_client/socket_io_client.dart' as IO;

class DriverSocketService {
  static final DriverSocketService _instance = DriverSocketService._internal();
  factory DriverSocketService() => _instance;
  DriverSocketService._internal();

  late IO.Socket socket;

  bool _isConnected = false;
  
  String? _vehicleType;
  
  void connect(String driverId, double lat, double lng, {String? vehicleType, bool isOnline = true}) {
    // Store vehicle type for future use
    if (vehicleType != null) {
      _vehicleType = vehicleType;
    }
    
    print('🔌 Connecting socket with status: ${isOnline ? "Online" : "Offline"}');
    
    // If already connected, just register the driver again
    if (_isConnected) {
      print('🔄 Socket already connected, re-registering driver with status: ${isOnline ? "Online" : "Offline"}');
      socket.emit('registerDriver', {
        'driverId': driverId,
        'lat': lat,
        'lng': lng,
        'vehicleType': _vehicleType,
        'isOnline': isOnline,
      });
      return;
    }
    
    socket = IO.io(
      'http://192.168.190.33:5002',
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
      _isConnected = true;
      socket.emit('registerDriver', {
        'driverId': driverId,
        'lat': lat,
        'lng': lng,
        'vehicleType': _vehicleType,
        'isOnline': isOnline,
      });
    });
    
    socket.onConnectError((error) {
      print('❌ Socket connection error: $error');
      _isConnected = false;
    });
    
    socket.onDisconnect((_) {
      print('🔴 Socket disconnected');
      _isConnected = false;
    });
    
    socket.onReconnect((_) {
      print('🔄 Socket reconnected');
      _isConnected = true;
      socket.emit('registerDriver', {
        'driverId': driverId,
        'lat': lat,
        'lng': lng,
        'vehicleType': _vehicleType,
        'isOnline': isOnline,
      });
    });

    // Listen to all possible trip request event types
    socket.on('newRideRequest', (data) {
      print('📩 New ride request: $data');
      if (onRideRequest != null) onRideRequest!(data);
    });
    
    socket.on('tripRequest', (data) {
      print('📩 Trip request: $data');
      if (onRideRequest != null) onRideRequest!(data);
    });
    
    socket.on('shortTripRequest', (data) {
      print('📩 Short trip request: $data');
      if (onRideRequest != null) onRideRequest!(data);
    });
    
    socket.on('parcelTripRequest', (data) {
      print('📩 Parcel trip request: $data');
      if (onRideRequest != null) onRideRequest!(data);
    });
    
    socket.on('longTripRequest', (data) {
      print('📩 Long trip request: $data');
      if (onRideRequest != null) onRideRequest!(data);
    });
  }

  void updateDriverLocation(String driverId, double lat, double lng) {
    if (!_isConnected) {
      print('⚠️ Socket not connected, cannot update driver location');
      return;
    }
    
    socket.emit('updateDriverLocation', {
      'driverId': driverId,
      'lat': lat,
      'lng': lng,
    });
  }
  
  void updateDriverStatus(String driverId, bool isOnline, double lat, double lng, String vehicleType) {
    print('🔄 Attempting to update driver status via socket: ${isOnline ? "Online" : "Offline"}');
    
    if (!_isConnected) {
      print('⚠️ Socket not connected, cannot update driver status');
      return;
    }
    
    final payload = {
      'driverId': driverId,
      'isOnline': isOnline,
      'lat': lat,
      'lng': lng,
      'vehicleType': vehicleType,
    };
    
    print('📤 Emitting driverStatusUpdate event with payload: $payload');
    socket.emit('driverStatusUpdate', payload);
    
    print('📡 Driver status updated via socket: ${isOnline ? "Online" : "Offline"}');
  }

  void acceptRide(
    String driverId,
    String userId,
    Map<String, dynamic> rideData,
  ) {
    if (!_isConnected) {
      print('⚠️ Socket not connected, cannot accept ride');
      return;
    }
    
    socket.emit('rideAccepted', {
      'driverId': driverId,
      'userId': userId,
      'rideData': rideData,
    });
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

  Function(Map<String, dynamic>)? onRideRequest;
}
