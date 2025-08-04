import 'package:socket_io_client/socket_io_client.dart' as IO;

class DriverSocketService {
  static final DriverSocketService _instance = DriverSocketService._internal();
  factory DriverSocketService() => _instance;
  DriverSocketService._internal();

  late IO.Socket socket;

  void connect(String driverId, double lat, double lng) {
    socket = IO.io(
      'http://192.168.210.12:5002',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );

    socket.onConnect((_) {
      print('🟢 Driver socket connected');
      socket.emit('registerDriver', {
        'driverId': driverId,
        'lat': lat,
        'lng': lng,
      });
    });

    socket.on('newRideRequest', (data) {
      print('📩 New ride request: $data');
      if (onRideRequest != null) onRideRequest!(data);
    });
  }

  void updateDriverLocation(String driverId, double lat, double lng) {
    socket.emit('updateDriverLocation', {
      'driverId': driverId,
      'lat': lat,
      'lng': lng,
    });
  }

  void acceptRide(
    String driverId,
    String userId,
    Map<String, dynamic> rideData,
  ) {
    socket.emit('rideAccepted', {
      'driverId': driverId,
      'userId': userId,
      'rideData': rideData,
    });
  }

  void rejectRide(String driverId, String userId) {
    socket.emit('rideRejected', {'driverId': driverId, 'userId': userId});
  }

  void disconnect() {
    socket.disconnect();
  }

  Function(Map<String, dynamic>)? onRideRequest;
}
