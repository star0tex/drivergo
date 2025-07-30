import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> sendOtp({
    required String phoneNumber,
    required Function(String) onCodeSent,
    required Function(String) onVerificationCompleted,
    required Function(String) onError,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
          onVerificationCompleted("Phone number automatically verified");
        },
        verificationFailed: (FirebaseAuthException e) {
          onError(e.message ?? "Verification failed");
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId); 
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          onCodeSent(verificationId);
        },
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  Future<void> verifyOtp({
    required String verificationId,
    required String otp,
    required Function(String) onSuccess,
    required Function(String) onError,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otp,
      );
      await _auth.signInWithCredential(credential);
      onSuccess("Phone number verified successfully");
    } catch (e) {
      onError(e.toString());
    }
  }
}
