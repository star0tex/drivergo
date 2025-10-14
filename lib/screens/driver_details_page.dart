import 'dart:convert';
import 'dart:io';
import 'package:drivergoo/screens/documents_review_page.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

// ✅ ADD THEME CLASSES
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
        color: AppColors.onSurface,
      );
}

class DriverDocumentUploadPage extends StatefulWidget {
  final String driverId;

  const DriverDocumentUploadPage({super.key, required this.driverId});

  @override
  State<DriverDocumentUploadPage> createState() =>
      _DriverDocumentUploadPageState();
}

class _DriverDocumentUploadPageState extends State<DriverDocumentUploadPage> {
  String? vehicleType;
  int currentStep = 0;
  final Map<String, File?> uploadedDocs = {};
  final Map<String, String?> extractedDataMap = {};
  File? profilePhoto;
  final picker = ImagePicker();

  final String backendUrl = "https://cd4ec7060b0b.ngrok-free.app";

  Future<String?> getToken() async =>
      await FirebaseAuth.instance.currentUser!.getIdToken();

  Future<String> extractTextFromImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final RecognizedText recognizedText = await textRecognizer.processImage(
      inputImage,
    );
    await textRecognizer.close();
    return recognizedText.text;
  }

  Map<String, String?> extractDocumentData(String ocrText, String docType) {
    final Map<String, String?> extracted = {};
    switch (docType.toLowerCase()) {
      case 'aadhaar':
        extracted['aadhaarNumber'] = RegExp(
          r'\b\d{4}\s\d{4}\s\d{4}\b',
        ).stringMatch(ocrText);
        break;
      case 'pan':
        extracted['panNumber'] = RegExp(
          r'[A-Z]{5}[0-9]{4}[A-Z]',
        ).stringMatch(ocrText);
        break;
      case 'license':
        extracted['dlNumber'] = RegExp(
          r'\b[A-Z]{2}\d{2} ?\d{11}\b',
        ).stringMatch(ocrText);
        break;
      case 'rc':
        extracted['rcNumber'] = RegExp(
          r'[A-Z]{2}\d{2}[A-Z]{1,2}\d{4}',
        ).stringMatch(ocrText);
        break;
      case 'insurance':
        extracted['policyNumber'] = RegExp(
          r'\b\d{10,15}\b',
        ).stringMatch(ocrText);
        break;
      case 'permit':
      case 'fitnesscertificate':
        extracted['permitNumber'] = RegExp(
          r'\b[A-Z0-9]{6,}\b',
        ).stringMatch(ocrText);
        break;
      default:
        extracted['raw'] = ocrText;
    }
    return extracted;
  }

  List<String> getRequiredDocs(String type) {
    switch (type) {
      case 'bike':
        return ['license', 'rc', 'aadhaar'];
      case 'auto':
        return ['license', 'rc', 'pan', 'aadhaar', 'fitnessCertificate'];
      case 'car':
        return [
          'license',
          'rc',
          'pan',
          'aadhaar',
          'insurance',
          'permit',
          'fitnessCertificate',
        ];
      default:
        return [];
    }
  }

  Future<void> pickAndUpload(String docType, String side, {bool fromCamera = false}) async {
    final picked = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    );
    if (picked == null) return;

    final file = File(picked.path);
    setState(() => uploadedDocs["${docType}_$side"] = file);

    final ocrText = await extractTextFromImage(file);
    final extracted = extractDocumentData(ocrText, docType);

    setState(() {
      extractedDataMap["${docType}_$side"] = jsonEncode(extracted);
    });

    final uri = Uri.parse("$backendUrl/api/driver/uploadDocument");
    final request = http.MultipartRequest("POST", uri);

    final token = await getToken();
    request.headers['Authorization'] = 'Bearer $token';

    String getMimeType(String path) {
      final ext = path.toLowerCase();
      if (ext.endsWith(".png")) return "image/png";
      if (ext.endsWith(".jpg") || ext.endsWith(".jpeg")) return "image/jpeg";
      return "application/octet-stream";
    }

    final mimeType = getMimeType(file.path);
    request.files.add(
      await http.MultipartFile.fromPath(
        "document",
        file.path,
        contentType: MediaType.parse(mimeType),
      ),
    );

    request.fields['docType'] = docType;
    request.fields['docSide'] = side;
    request.fields['vehicleType'] = vehicleType!;
    request.fields['extractedData'] = jsonEncode(extracted);

    try {
      final response = await request.send();
      final res = await http.Response.fromStream(response);
      print("✅ $docType ($side) upload response: ${res.body}");
    } catch (e) {
      print("❌ Upload failed: $e");
    }
  }

  Future<void> uploadProfilePhoto() async {
    if (profilePhoto == null) return;
    final uri = Uri.parse("$backendUrl/api/driver/uploadProfilePhoto");
    final request = http.MultipartRequest("POST", uri);
    request.headers['Authorization'] = 'Bearer ${await getToken()}';
    
    String getMimeType(String path) {
      final ext = path.toLowerCase();
      if (ext.endsWith(".png")) return "image/png";
      if (ext.endsWith(".jpg") || ext.endsWith(".jpeg")) return "image/jpeg";
      return "image/jpeg";
    }

    final mimeType = getMimeType(profilePhoto!.path);

    request.files.add(
      await http.MultipartFile.fromPath(
        "image",
        profilePhoto!.path,
        contentType: MediaType.parse(mimeType),
      ),
    );
    final response = await request.send();
    final res = await http.Response.fromStream(response);
    print("✅ Profile photo uploaded: ${res.body}");
  }

  Widget buildDocBox(String docType) {
    final frontFile = uploadedDocs["${docType}_front"];
    final backFile = uploadedDocs["${docType}_back"];

    Widget buildSide(String side, File? file) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  side == 'front' ? Icons.credit_card : Icons.flip_to_back,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  "${docType.toUpperCase()} - ${side.toUpperCase()}",
                  style: AppTextStyles.heading3,
                ),
              ],
            ),
            const SizedBox(height: 16),
            file != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      file,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  )
                : Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.divider,
                        width: 2,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.upload_file,
                          size: 48,
                          color: AppColors.onSurfaceTertiary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "No file selected",
                          style: AppTextStyles.body2,
                        ),
                      ],
                    ),
                  ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => pickAndUpload(docType, side, fromCamera: false),
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: Text(
                      "Gallery",
                      style: AppTextStyles.button.copyWith(
                        color: AppColors.onPrimary,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => pickAndUpload(docType, side, fromCamera: true),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: Text(
                      "Camera",
                      style: AppTextStyles.button.copyWith(fontSize: 14),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSide("front", frontFile),
        buildSide("back", backFile),
      ],
    );
  }

  Widget buildStepContent() {
    if (vehicleType == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.directions_car,
            size: 80,
            color: AppColors.primary,
          ),
          const SizedBox(height: 24),
          Text(
            "Select Your Vehicle Type",
            style: AppTextStyles.heading2,
          ),
          const SizedBox(height: 8),
          Text(
            "Choose the type of vehicle you'll be driving",
            style: AppTextStyles.body2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          for (var type in ['bike', 'auto', 'car'])
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildVehicleTypeButton(type),
            ),
        ],
      );
    } else if (currentStep < getRequiredDocs(vehicleType!).length) {
      final docType = getRequiredDocs(vehicleType!)[currentStep];
      final totalDocs = getRequiredDocs(vehicleType!).length;
      
      return Column(
        children: [
          // Progress indicator
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Step ${currentStep + 1} of $totalDocs",
                  style: AppTextStyles.body1,
                ),
                Text(
                  "${((currentStep / totalDocs) * 100).toStringAsFixed(0)}%",
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: currentStep / totalDocs,
            backgroundColor: AppColors.surface,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 6,
          ),
          const SizedBox(height: 24),
          buildDocBox(docType),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => setState(() => currentStep++),
              icon: const Icon(Icons.arrow_forward),
              label: Text(
                "Next Document",
               
                style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          Icon(
            Icons.account_circle,
            size: 80,
            color: AppColors.primary,
          ),
          const SizedBox(height: 24),
          Text(
            "Upload Profile Photo",
            style: AppTextStyles.heading2,
          ),
          const SizedBox(height: 8),
          Text(
            "Add a clear photo of yourself for your profile",
            style: AppTextStyles.body2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                profilePhoto != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          profilePhoto!,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.divider,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person,
                              size: 64,
                              color: AppColors.onSurfaceTertiary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "No photo selected",
                              style: AppTextStyles.body2,
                            ),
                          ],
                        ),
                      ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (picked != null) {
                        setState(() => profilePhoto = File(picked.path));
                      }
                    },
                    icon: const Icon(Icons.photo_library),
                    label: Text(
                      "Select Photo from Gallery",
                      style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
  width: double.infinity,
  child: ElevatedButton.icon(
    onPressed: () async {
      // ✅ First upload the profile photo
      await uploadProfilePhoto();

      // ✅ Then navigate to DocumentsReviewPage with driverId
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DocumentsReviewPage(
            driverId: widget.driverId, // ✅ Pass the driverId
          ),
        ),
      );
    },
    icon: const Icon(Icons.check_circle),
    label: Text(
      "Finish Registration",
      style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.success,
      foregroundColor: AppColors.onPrimary,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
    ),
  ),
),
              ],
            ),
          ),
        ],
      );
    }
  }

  Widget _buildVehicleTypeButton(String type) {
    IconData icon;
    String label;
    
    switch (type) {
      case 'bike':
        icon = Icons.two_wheeler;
        label = 'BIKE';
        break;
      case 'auto':
        icon = Icons.airport_shuttle;
        label = 'AUTO';
        break;
      case 'car':
        icon = Icons.directions_car;
        label = 'CAR';
        break;
      default:
        icon = Icons.help;
        label = type.toUpperCase();
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () async {
          print("🚗 Attempting to set vehicle type: $type");
          
          final token = await getToken();
          if (token == null) {
            print("❌ No Firebase token available");
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Authentication error. Please login again.')),
            );
            return;
          }

          final uri = Uri.parse("$backendUrl/api/driver/setVehicleType");
          try {
            print("📤 Sending vehicle type to backend...");
            final res = await http.post(
              uri,
              headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer $token"
              },
              body: jsonEncode({
                "vehicleType": type,
              }),
            );

            print("📥 Backend response status: ${res.statusCode}");
            print("📥 Backend response body: ${res.body}");

            if (res.statusCode == 200) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString("vehicleType", type);
              
              setState(() => vehicleType = type);
              
              print("✅ Vehicle type '$type' set successfully");
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Vehicle type set to ${type.toUpperCase()}'),
                  backgroundColor: AppColors.success,
                ),
              );
            } else {
              print("❌ Failed to set vehicle type: ${res.body}");
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to set vehicle type: ${res.body}'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          } catch (e) {
            print("🔥 Error setting vehicle type: $e");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $e'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTextStyles.button.copyWith(
                color: AppColors.onPrimary,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          "Driver Registration",
          style: AppTextStyles.heading3.copyWith(color: AppColors.onPrimary),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.onPrimary),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: buildStepContent(),
        ),
      ),
    );
  }
}