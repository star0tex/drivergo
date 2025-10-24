import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:drivergoo/services/background_service.dart';

import 'firebase_options.dart'; // ✅ This must be here!
import 'package:drivergoo/screens/splash_screen.dart';
Future<void> requestBatteryOptimizationExemption() async {
  if (Platform.isAndroid) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // ✅ Required!
  );

  await FirebaseMessaging.instance.requestPermission();
 await TripBackgroundService.initializeService();
  
  // ✅ Request battery exemption
  await requestBatteryOptimizationExemption();
  runApp(const IndianRideDriverApp());
}

class IndianRideDriverApp extends StatelessWidget {
  const IndianRideDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Indian Ride - Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SplashScreen(),
    );
  }
}
