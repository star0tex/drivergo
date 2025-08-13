import 'dart:convert';
import 'package:drivergoo/screens/driver_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';

class DriverLoginPage extends StatefulWidget {
  const DriverLoginPage({super.key});

  @override
  State<DriverLoginPage> createState() => _DriverLoginPageState();
}

class _DriverLoginPageState extends State<DriverLoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  String _verificationId = '';
  bool _codeSent = false;
  bool _autoVerified = false;

  Future<void> _routeDriver(String phoneOnly) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError("Login failed. Firebase user is null.");
      return;
    }

    _showLoadingDialog();

    String token = await user.getIdToken() ?? '';
    if (token.isEmpty) {
      Navigator.pop(context);
      _showError("Token is empty.");
      return;
    }

    int attempts = 0;
    bool tokenValid = false;

    while (attempts < 10) {
      try {
        final decoded = JwtDecoder.decode(token);
        if (decoded.containsKey("phone_number") || decoded.containsKey("uid")) {
          tokenValid = true;
          break;
        }
      } catch (_) {}

      await Future.delayed(const Duration(seconds: 1));
      token = await user.getIdToken(true) ?? '';
      attempts++;
    }

    if (!tokenValid) {
      Navigator.pop(context);
      _showError("Login failed. Please try again.");
      return;
    }

    try {
      final res = await http.post(
        Uri.parse("http://192.168.210.12:5002/api/auth/firebase-login"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "phone": "+91$phoneOnly",
          "role": "driver", // ✅ required for backend to register as driver
        }),
      );

      Navigator.pop(context);

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final isNewUser = data["newUser"] == true;
        _showSuccess(isNewUser ? "Welcome, driver!" : "Welcome back!");

        final driverId = data["user"]["phone"]; // or data["user"]["_id"]
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DriverDocumentUploadPage(driverId: driverId),
          ),
        );
      } else {
        _showError("Login failed: ${res.body}");
      }
    } catch (e) {
      Navigator.pop(context);
      _showError("Connection error: $e");
    }
  }

  Future<void> _sendOTP() async {
    await FirebaseAuth.instance.signOut();
    setState(() {
      _codeSent = false;
      _verificationId = '';
      _otpController.clear();
    });

    final rawPhone = _phoneController.text.trim();
    if (rawPhone.length != 10) {
      _showError("Please enter a valid 10-digit phone number.");
      return;
    }

    final String phone = "+91$rawPhone";

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final userCred = await FirebaseAuth.instance.signInWithCredential(
              credential,
            );
            if (userCred.user != null) {
              _autoVerified = true;
              await _routeDriver(rawPhone);
            }
          } catch (e) {
            _showError("Auto-verification failed.");
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          _showError("Verification failed: ${e.message}");
        },
        codeSent: (String verId, int? resendToken) {
          setState(() {
            _verificationId = verId;
            _codeSent = true;
          });
          Future.delayed(
            const Duration(milliseconds: 100),
            () => _otpFocus.requestFocus(),
          );
        },
        codeAutoRetrievalTimeout: (String verId) {
          _verificationId = verId;
        },
      );
    } catch (e) {
      _showError("Failed to send OTP: $e");
    }
  }

  Future<void> _verifyOTP() async {
    if (_autoVerified) return;

    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showError("Enter the 6-digit OTP.");
      return;
    }

    if (_verificationId.isEmpty) {
      _showError("Verification ID not found. Please request OTP again.");
      return;
    }

    final PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: otp,
    );

    try {
      final userCred = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      if (userCred.user == null) {
        throw Exception("Firebase user is null");
      }
      await _routeDriver(_phoneController.text.trim());
    } catch (e) {
      if (FirebaseAuth.instance.currentUser != null) {
        await _routeDriver(_phoneController.text.trim());
        return;
      }
      _showError("Invalid OTP: ${e.toString()}");
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Logging you in...", style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Driver Login',
                style: TextStyle(
                  fontSize: 26,
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                'Enter your mobile number',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  prefixText: '+91 ',
                  hintText: '0000000000',
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 20),
              if (_codeSent)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Enter OTP', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _otpController,
                      focusNode: _otpFocus,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(6),
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        hintText: '6-digit OTP',
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        counterText: '',
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _codeSent ? _verifyOTP : _sendOTP,
                  child: Text(_codeSent ? 'Verify OTP' : 'Send OTP'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _otpFocus.dispose();
    super.dispose();
  }
}
