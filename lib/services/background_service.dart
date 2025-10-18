import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'socket_service.dart';

class TripBackgroundService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// ✅ Initialize background service
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // Create notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'active_trip_channel',
      'Active Trip',
      description: 'Shows when you have an active trip',
      importance: Importance.high,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: false,
        autoStartOnBoot: true, // ✅ auto restart after reboot
      ),
    );
  }

  /// ✅ Start background service for active trip
  static Future<void> startTripService({
    required String tripId,
    required String driverId,
    required String customerName,
  }) async {
    await WakelockPlus.enable();
    final service = FlutterBackgroundService();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_tripId', tripId);
    await prefs.setString('bg_driverId', driverId);
    await prefs.setString('bg_customerName', customerName);
    await prefs.setBool('bg_service_running', true);

    await service.startService();
    print('🚀 Background service started for trip: $tripId');
  }

  /// ✅ Stop background service
  static Future<void> stopTripService() async {
    await WakelockPlus.disable();

    final service = FlutterBackgroundService();
    service.invoke('stop');

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bg_tripId');
    await prefs.remove('bg_driverId');
    await prefs.remove('bg_customerName');
    await prefs.setBool('bg_service_running', false);

    print('🛑 Background service stopped');
  }

  /// ✅ Check if service is running
  static Future<bool> isServiceRunning() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('bg_service_running') ?? false;
  }

  /// ✅ Background service entry point
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final tripId = prefs.getString('bg_tripId');
    final driverId = prefs.getString('bg_driverId');
    final customerName = prefs.getString('bg_customerName') ?? 'Customer';

    if (tripId == null || driverId == null) {
      service.stopSelf();
      return;
    }

    // Show persistent notification
    await _showNotification(
      title: 'Active Trip',
      body: 'Trip with $customerName is in progress',
    );

    // ✅ Keep socket alive in background isolate
    final socketService = DriverSocketService();
final vehicleType = prefs.getString('vehicleType') ?? 'bike';
final isOnline = prefs.getBool('isOnline') ?? true;

final lastLat = double.tryParse(prefs.getString('lastLat') ?? '') ?? 0.0;
final lastLng = double.tryParse(prefs.getString('lastLng') ?? '') ?? 0.0;

socketService.connect(
  driverId,
  lastLat,
  lastLng,
  vehicleType: vehicleType,
  isOnline: isOnline,
);

    // Listen for stop command
    service.on('stop').listen((event) {
      socketService.disconnect();
      service.stopSelf();
      WakelockPlus.disable();
    });

    // Periodic keep-alive check
    Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!(await (service as AndroidServiceInstance).isForegroundService())) {
        timer.cancel();
        return;
      }

      final tripStillActive = await _isTripStillActive(tripId);

      if (!tripStillActive) {
        print('✅ Trip completed - stopping background service');
        timer.cancel();
        socketService.disconnect();
        service.stopSelf();
        await WakelockPlus.disable();
      } else {
        print('💓 Trip still active - keeping socket alive');
      }
    });
  }

  /// ✅ iOS background handler
  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  /// ✅ Show persistent notification
  static Future<void> _showNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'active_trip_channel',
      'Active Trip',
      channelDescription: 'Shows when you have an active trip',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      888,
      title,
      body,
      details,
    );
  }

  /// ✅ Check if trip is still active
  static Future<bool> _isTripStillActive(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    final activeTripId = prefs.getString('activeTripId');
    final hasActiveTrip = prefs.getBool('hasActiveTrip') ?? false;

    return hasActiveTrip && activeTripId == tripId;
  }
}
