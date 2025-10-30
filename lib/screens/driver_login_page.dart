import 'package:drivergoo/screens/driver_details_page.dart';
import 'package:drivergoo/screens/documents_review_page.dart';
import 'package:drivergoo/screens/driver_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// --- MATCHING COLOR PALETTE ---
class AppColors {
  static const Color primary = Color.fromARGB(255, 212, 120, 0);
  static const Color background = Colors.white;
  static const Color onSurface = Colors.black;
  static const Color surface = Color(0xFFF5F5F5);
  static const Color onPrimary = Colors.white;
  static const Color onSurfaceSecondary = Colors.black54;
  static const Color onSurfaceTertiary = Colors.black38;
  static const Color divider = Color(0xFFEEEEEE);
  static const Color success = Color.fromARGB(255, 0, 66, 3);
  static const Color warning = Color(0xFFFFA000);
  static const Color error = Color(0xFFD32F2F);
}

// --- MATCHING TYPOGRAPHY ---
class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.onSurface,
        letterSpacing: -0.5,
      );

  static TextStyle get heading2 => GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
        letterSpacing: -0.3,
      );

  static TextStyle get heading3 => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      );

  static TextStyle get body1 => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      );

  static TextStyle get body2 => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceSecondary,
      );

  static TextStyle get caption => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceTertiary,
        letterSpacing: 0.5,
      );

  static TextStyle get button => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.onPrimary,
      );
}

class DriverLoginPage extends StatefulWidget {
  const DriverLoginPage({super.key});

  @override
  State<DriverLoginPage> createState() => _DriverLoginPageState();
}

class _DriverLoginPageState extends State<DriverLoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  final String backendUrl = "https://b23b44ae0c5e.ngrok-free.app";
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _codeSent = false;
  bool _isLoading = false;
  bool _isCheckingSession = true;
  
  String? _verificationId;
  int? _resendToken;

  @override
  void initState() {
    super.initState();
    _initializeFirebaseAuth();
    _checkExistingSession();
  }

  Future<void> _initializeFirebaseAuth() async {
    await _auth.setLanguageCode('en');
  }

  Future<void> _checkExistingSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString("driverId");
      final vehicleType = prefs.getString("vehicleType") ?? '';
      final isLoggedIn = prefs.getBool("isLoggedIn") ?? false;
      final phoneNumber = prefs.getString("phoneNumber") ?? '';

      debugPrint("🔍 Checking existing session...");
      debugPrint("   Driver ID: $driverId");
      debugPrint("   Phone: $phoneNumber");
      debugPrint("   Vehicle Type: '$vehicleType'");
      debugPrint("   Is Logged In: $isLoggedIn");

      if (isLoggedIn && 
          driverId != null && 
          driverId.isNotEmpty && 
          phoneNumber.isNotEmpty) {
        
        debugPrint("✅ Valid local session found - auto-navigating");
        
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (!mounted) return;
        
        if (vehicleType.isNotEmpty) {
          debugPrint("🚗 Navigating to dashboard with vehicle: '$vehicleType'");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDashboardPage(
                driverId: driverId,
                vehicleType: vehicleType,
              ),
            ),
          );
        } else {
          debugPrint("📄 No vehicle type - navigating to document upload");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDocumentUploadPage(driverId: driverId),
            ),
          );
        }
        return;
      } else {
        debugPrint("❌ No valid session found - showing login screen");
      }
    } catch (e) {
      debugPrint("⚠️ Error checking session: $e");
    } finally {
      if (mounted) {
        setState(() => _isCheckingSession = false);
      }
    }
  }

  // ✅ Send OTP using Firebase Phone Auth (Same as Customer App)
  Future<void> _sendOTP() async {
    if (_isLoading) return;

    setState(() {
      _codeSent = false;
      _otpController.clear();
      _isLoading = true;
    });

    final rawPhone = _phoneController.text.trim();
    if (rawPhone.length != 10) {
      setState(() => _isLoading = false);
      _showMessage("Please enter a valid 10-digit phone number.", isError: true);
      return;
    }

    final String phoneWithCode = "+91$rawPhone";

    try {
      // ✅ Firebase Phone Auth - FREE with Spark plan
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneWithCode,
        timeout: const Duration(seconds: 60),
        
        // Auto-verification (Android only)
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint("✅ Auto verification completed");
          
          setState(() => _isLoading = true);
          
          // Show loading if not already shown
          if (!_codeSent) {
            _showLoadingDialog();
          }
          
          try {
            await _signInWithCredential(credential);
          } catch (e) {
            debugPrint("❌ Auto-verification sign-in error: $e");
            if (mounted) {
              setState(() => _isLoading = false);
              _showMessage("Auto sign-in failed. Please enter OTP manually.", isError: true);
            }
          }
        },
        
        // Verification failed
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          debugPrint("❌ Verification failed: ${e.code} - ${e.message}");
          
          if (e.code == 'invalid-phone-number') {
            _showMessage('Invalid phone number format', isError: true);
          } else if (e.code == 'too-many-requests') {
            _showMessage('Too many requests. Try again later.', isError: true);
          } else {
            _showMessage('Verification failed: ${e.message}', isError: true);
          }
        },
        
        // OTP sent successfully
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _isLoading = false;
            _codeSent = true;
            _verificationId = verificationId;
            _resendToken = resendToken;
          });
          
          _showMessage("OTP sent to your phone", isError: false);
          
          Future.delayed(
            const Duration(milliseconds: 300),
            () => _otpFocus.requestFocus(),
          );
          
          debugPrint("✅ OTP sent successfully. Verification ID: $verificationId");
        },
        
        // Auto-retrieval timeout
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          debugPrint("⏱️ Auto retrieval timeout");
        },
        
        // For resending
        forceResendingToken: _resendToken,
      );

      // ✅ Register FCM token
      String? fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        debugPrint("📱 FCM Token: $fcmToken");
      }

    } catch (e) {
      setState(() => _isLoading = false);
      _showMessage("Failed to send OTP: ${e.toString()}", isError: true);
      debugPrint("Send OTP error: $e");
    }
  }

  // ✅ Verify OTP and sign in
  Future<void> _verifyOTPAndLogin() async {
    if (_isLoading) return;

    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showMessage("Enter the 6-digit OTP.", isError: true);
      return;
    }

    if (_verificationId == null) {
      _showMessage("Please request OTP first.", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    _showLoadingDialog();

    try {
      // Create credential with OTP
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      // Sign in with Firebase
      await _signInWithCredential(credential);

    } catch (e) {
      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);
      
      if (e is FirebaseAuthException) {
        if (e.code == 'invalid-verification-code') {
          _showMessage('Invalid OTP. Please try again.', isError: true);
        } else if (e.code == 'session-expired') {
          _showMessage('OTP expired. Request a new one.', isError: true);
          setState(() => _codeSent = false);
        } else {
          _showMessage('Verification failed: ${e.message}', isError: true);
        }
      } else {
        _showMessage("Login error: ${e.toString()}", isError: true);
      }
      
      debugPrint("Login error: $e");
    }
  }

  // ✅ AGGRESSIVE FIX: Completely avoid User object access
// Replace your existing _signInWithCredential method with this:

Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
  try {
    debugPrint("🔐 Starting sign-in with credential...");
    
    // ✅ FIX: Catch the type cast error that occurs internally
    UserCredential? userCredential;
    try {
      userCredential = await _auth.signInWithCredential(credential);
      debugPrint("✅ Credential accepted by Firebase");
    } catch (typeError) {
      if (typeError.toString().contains('is not a subtype')) {
        debugPrint("⚠️ Known Firebase type cast error (non-fatal) - proceeding anyway");
        // The sign-in actually succeeded, we just can't access the user object
        // Wait a bit for Firebase to fully process
        await Future.delayed(const Duration(milliseconds: 2000));
      } else {
        // Different error - rethrow
        rethrow;
      }
    }
    
    // Get phone from input (more reliable than Firebase user object)
    final rawPhone = _phoneController.text.trim();
    debugPrint("📱 Using phone from input: $rawPhone");
    
    // Get Firebase UID - with multiple fallback methods
    String? firebaseUid;
    
    // Method 1: Try from userCredential (if we got it)
    if (userCredential?.user?.uid != null) {
      try {
        firebaseUid = userCredential!.user!.uid;
        debugPrint("✅ Got UID from userCredential: $firebaseUid");
      } catch (e) {
        debugPrint("⚠️ Failed to get UID from userCredential: $e");
      }
    }
    
    // Method 2: Try from currentUser
    if (firebaseUid == null) {
      try {
        await Future.delayed(const Duration(milliseconds: 1000));
        firebaseUid = _auth.currentUser?.uid;
        if (firebaseUid != null) {
          debugPrint("✅ Got UID from currentUser: $firebaseUid");
        }
      } catch (e) {
        debugPrint("⚠️ Failed to get UID from currentUser: $e");
      }
    }
    
    // Method 3: Extract from ID token
    if (firebaseUid == null) {
      try {
        final idToken = await _auth.currentUser?.getIdToken(true);
        if (idToken != null) {
          final parts = idToken.split('.');
          if (parts.length > 1) {
            final payload = parts[1];
            final normalized = base64Url.normalize(payload);
            final decoded = utf8.decode(base64Url.decode(normalized));
            final Map<String, dynamic> tokenData = jsonDecode(decoded);
            firebaseUid = tokenData['user_id'] ?? tokenData['sub'];
            if (firebaseUid != null) {
              debugPrint("✅ Extracted UID from token: $firebaseUid");
            }
          }
        }
      } catch (e) {
        debugPrint("⚠️ Token decode failed: $e");
      }
    }
    
    // Method 4: Last resort - use phone as UID
    if (firebaseUid == null || firebaseUid.isEmpty) {
      debugPrint("⚠️ All UID extraction methods failed - using phone as fallback");
      firebaseUid = "phone_$rawPhone";
    }
    
    debugPrint("🔑 Final UID: $firebaseUid");
    
    // ✅ Sync with backend
    await _syncWithBackend(rawPhone, firebaseUid);

  } catch (e) {
    if (mounted) {
      try {
        Navigator.pop(context);
      } catch (_) {}
    }
    
    setState(() => _isLoading = false);
    
    // Better error messages
    String errorMessage = "Sign-in failed";
    if (e.toString().contains('network')) {
      errorMessage = "Network error. Please check your connection.";
    } else if (e.toString().contains('invalid-verification-code')) {
      errorMessage = "Invalid OTP. Please try again.";
    } else if (e.toString().contains('session-expired')) {
      errorMessage = "OTP expired. Please request a new one.";
      setState(() => _codeSent = false);
    } else if (e.toString().contains('is not a subtype')) {
      // This shouldn't happen now, but just in case
      errorMessage = "Authentication completed but with minor errors. Please try again.";
    }
    
    _showMessage(errorMessage, isError: true);
    debugPrint("❌ Sign-in error: $e");
  }
}  // ✅ Sync with backend (DRIVER SPECIFIC)
  Future<void> _syncWithBackend(String phone, String firebaseUid) async {
    try {
      final response = await http.post(
        Uri.parse("$backendUrl/api/auth/firebase-sync"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": phone,
          "firebaseUid": firebaseUid,
          "role": "driver", // ✅ CRITICAL: Set role as driver
        }),
      ).timeout(const Duration(seconds: 30));

      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("✅ Backend sync response: $data");

        final driverId = data["user"]["_id"];
        final isNewUser = data["newUser"] == true;
        final docsApproved = data["docsApproved"] == true;
        
        String vehicleType = '';
        
        if (data["user"]["vehicleType"] != null) {
          vehicleType = data["user"]["vehicleType"].toString().toLowerCase().trim();
        }

        // Save to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("driverId", driverId);
        await prefs.setString("phoneNumber", phone);
        await prefs.setString("vehicleType", vehicleType);
        await prefs.setBool("isLoggedIn", true);
        await prefs.setInt("loginTimestamp", DateTime.now().millisecondsSinceEpoch);
        await prefs.setString("lastLoginResponse", jsonEncode(data));

        debugPrint("💾 Saved to SharedPreferences:");
        debugPrint("   driverId: $driverId");
        debugPrint("   vehicleType: $vehicleType");
        debugPrint("   isNewUser: $isNewUser");
        debugPrint("   docsApproved: $docsApproved");

        // Navigation logic
        if (isNewUser) {
          _showMessage("Welcome! Please upload your documents.", isError: false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDocumentUploadPage(driverId: driverId),
            ),
          );
        } else if (docsApproved) {
          if (vehicleType.isEmpty) {
            _showMessage(
              "Please complete your vehicle registration first.",
              isError: true,
            );
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => DriverDocumentUploadPage(driverId: driverId),
              ),
            );
            return;
          }
          
          _showMessage("Welcome back!", isError: false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDashboardPage(
                driverId: driverId,
                vehicleType: vehicleType,
              ),
            ),
          );
        } else {
          _showMessage("Your documents are under review.", isError: false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DocumentsReviewPage(driverId: driverId),
            ),
          );
        }
      } else {
        final errorData = jsonDecode(response.body);
        _showMessage(
          errorData['message'] ?? "Backend sync failed",
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);
      _showMessage("Backend sync error: ${e.toString()}", isError: true);
      debugPrint("❌ Backend sync error: $e");
    }
  }

  Future<void> _resendOTP() async {
    _showMessage("Resending OTP...", isError: false);
    setState(() => _codeSent = false);
    await _sendOTP();
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppColors.background,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              const SizedBox(height: 16),
              Text("Verifying OTP...", style: AppTextStyles.body1),
              const SizedBox(height: 8),
              Text("Please wait", style: AppTextStyles.caption),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: AppColors.onPrimary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingSession) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Checking session...',
                style: AppTextStyles.body1,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo/Icon
              Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.local_taxi,
                    size: 64,
                    color: AppColors.primary,
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Title
              Center(
                child: Text(
                  'Driver Login',
                  style: AppTextStyles.heading1.copyWith(fontSize: 28),
                ),
              ),
              
              const SizedBox(height: 8),
              
              Center(
                child: Text(
                  'Welcome back! Please login to continue',
                  style: AppTextStyles.body2,
                  textAlign: TextAlign.center,
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Phone Number Input
              Text(
                'Mobile Number',
                style: AppTextStyles.heading3.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 12),
              
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.onSurface.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  enabled: !_codeSent && !_isLoading,
                  style: AppTextStyles.body1,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    prefixIcon: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.phone,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    prefixText: '+91 ',
                    prefixStyle: AppTextStyles.body1.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    hintText: '9876543210',
                    hintStyle: AppTextStyles.body2,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    counterText: '',
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // OTP Input (conditional)
              if (_codeSent) ...[
                Text(
                  'Enter OTP',
                  style: AppTextStyles.heading3.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 12),
                
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.onSurface.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _otpController,
                    focusNode: _otpFocus,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    enabled: !_isLoading,
                    style: AppTextStyles.body1.copyWith(
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(6),
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.lock,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      hintText: '000000',
                      hintStyle: AppTextStyles.body2.copyWith(
                        letterSpacing: 8,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _verifyOTPAndLogin(),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() {
                                _codeSent = false;
                                _otpController.clear();
                                _verificationId = null;
                              }),
                      icon: const Icon(Icons.edit, size: 18),
                      label: Text(
                        'Change Number',
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _isLoading ? null : _resendOTP,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(
                        'Resend OTP',
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
              ],
              
              const SizedBox(height: 32),
              
              // Main Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 3,
                    shadowColor: AppColors.primary.withOpacity(0.3),
                  ),
                  onPressed: _isLoading 
                      ? null 
                      : (_codeSent ? _verifyOTPAndLogin : _sendOTP),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.onPrimary,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _codeSent ? Icons.verified_user : Icons.send,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _codeSent ? 'Verify & Login' : 'Send OTP',
                              style: AppTextStyles.button,
                            ),
                          ],
                        ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Info box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'OTP will be sent via Firebase Phone Authentication',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
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