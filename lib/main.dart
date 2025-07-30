import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart'; // ✅ This must be here!
import 'package:drivergoo/screens/driver_login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // ✅ Required!
  );

  await FirebaseMessaging.instance.requestPermission();

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
      home: const DriverLoginPage(),
    );
  }
}
