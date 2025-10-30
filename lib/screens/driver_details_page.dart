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

// Theme classes (unchanged)
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
  final List<String>? uploadedDocTypes;

  const DriverDocumentUploadPage({
    super.key, 
    required this.driverId,
    this.uploadedDocTypes,
  });

  @override
  State<DriverDocumentUploadPage> createState() =>
      _DriverDocumentUploadPageState();
}

class _DriverDocumentUploadPageState extends State<DriverDocumentUploadPage> {
  String? vehicleType;
  int currentStep = 0;
  final Map<String, File?> uploadedDocs = {};
  final Map<String, String?> extractedDataMap = {};
  final Map<String, bool> uploadStatus = {};
  File? profilePhoto;
  final picker = ImagePicker();
  bool isUploading = false;
  List<String> requiredDocs = [];
  List<String> alreadyUploadedDocs = [];

  // ✅ NEW: Controllers for driver details
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _vehicleNumberController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _detailsSaved = false;

  final String backendUrl = "https://b23b44ae0c5e.ngrok-free.app";

  final Map<String, String> docTypeMapping = {
    'license': 'license',
    'pan': 'pan',
    'aadhaar': 'aadhaar',
    'insurance': 'insurance',
    'permit': 'permit',
    'fitnessCertificate': 'fitnessCertificate',
    'rc': 'rc',
  };

  @override
  void initState() {
    super.initState();
    alreadyUploadedDocs = widget.uploadedDocTypes ?? [];
    _loadVehicleTypeAndInitialize();
    _loadSavedDetails();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  Future<String?> getPhoneNumber() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if (user.phoneNumber != null) {
        return user.phoneNumber!.replaceAll(RegExp(r'[^\d]'), '');
      }
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('phoneNumber');
    }
    return null;
  }

  // ✅ NEW: Load saved details
  Future<void> _loadSavedDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('driverName');
    final savedVehicleNumber = prefs.getString('vehicleNumber');
    
    if (savedName != null) {
      _nameController.text = savedName;
    }
    if (savedVehicleNumber != null) {
      _vehicleNumberController.text = savedVehicleNumber;
    }
    
    _detailsSaved = (savedName != null && savedVehicleNumber != null);
  }

  // ✅ NEW: Save driver details to backend
  Future<void> _saveDriverDetails() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => isUploading = true);

    try {
      final token = await getToken();
      if (token == null) {
        throw Exception("Authentication failed");
      }

      final phoneNumber = await getPhoneNumber();
      if (phoneNumber == null) {
        throw Exception("Phone number not found");
      }

      final uri = Uri.parse("$backendUrl/api/driver/updateProfile");
      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token"
        },
        body: jsonEncode({
          "phoneNumber": phoneNumber,
          "name": _nameController.text.trim(),
          "vehicleNumber": _vehicleNumberController.text.trim().toUpperCase(),
          "vehicleType": vehicleType,
        }),
      );

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('driverName', _nameController.text.trim());
        await prefs.setString('vehicleNumber', _vehicleNumberController.text.trim().toUpperCase());
        
        setState(() {
          _detailsSaved = true;
          currentStep = 1; // Move to document upload
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Details saved successfully'),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        throw Exception("Failed to save details: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Error saving driver details: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save details: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => isUploading = false);
    }
  }

  Future<void> _loadVehicleTypeAndInitialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVehicleType = prefs.getString('vehicleType');
    
    if (savedVehicleType != null && savedVehicleType.isNotEmpty) {
      setState(() {
        vehicleType = savedVehicleType;
        requiredDocs = getRequiredDocs(savedVehicleType);
        
        if (alreadyUploadedDocs.isNotEmpty) {
          for (int i = 0; i < requiredDocs.length; i++) {
            if (!alreadyUploadedDocs.contains(requiredDocs[i])) {
              currentStep = i + 1; // +1 because step 0 is now vehicle details
              break;
            }
          }
          if (currentStep == 0 && alreadyUploadedDocs.length >= requiredDocs.length) {
            currentStep = requiredDocs.length + 1;
          }
        }
      });
    }
  }

  Future<String?> getToken() async =>
      await FirebaseAuth.instance.currentUser?.getIdToken();

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
      case 'driving_license':
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
      case 'fitness_certificate':
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
    switch (type.toLowerCase()) {
      case 'bike':
        return ['license', 'rc', 'pan', 'aadhaar'];
      case 'auto':
        return ['license', 'rc', 'pan', 'aadhaar', 'fitnessCertificate'];
      case 'car':
        return ['license', 'rc', 'pan', 'aadhaar', 'fitnessCertificate', 'permit', 'insurance'];
      default:
        return [];
    }
  }

  Future<void> pickAndUpload(String docType, String side, {bool fromCamera = false}) async {
    final picked = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      uploadedDocs["${docType}_$side"] = file;
      isUploading = true;
    });

    try {
      final ocrText = await extractTextFromImage(file);
      final extracted = extractDocumentData(ocrText, docType);

      setState(() {
        extractedDataMap["${docType}_$side"] = jsonEncode(extracted);
      });

      final uri = Uri.parse("$backendUrl/api/driver/uploadDocument");
      final request = http.MultipartRequest("POST", uri);

      final token = await getToken();
      if (token == null) throw Exception("Authentication failed");
      
      final phoneNumber = await getPhoneNumber();
      if (phoneNumber == null) throw Exception("Phone number not found");
      
      request.headers['Authorization'] = 'Bearer $token';

      String getMimeType(String path) {
        final ext = path.toLowerCase();
        if (ext.endsWith(".png")) return "image/png";
        if (ext.endsWith(".jpg") || ext.endsWith(".jpeg")) return "image/jpeg";
        if (ext.endsWith(".webp")) return "image/webp";
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

      final backendDocType = docTypeMapping[docType] ?? docType;
      request.fields['docType'] = backendDocType;
      request.fields['docSide'] = side;
      request.fields['vehicleType'] = vehicleType!;
      request.fields['phoneNumber'] = phoneNumber;
      request.fields['extractedData'] = jsonEncode(extracted);

      final response = await request.send();
      final res = await http.Response.fromStream(response);
      
      if (response.statusCode == 200) {
        setState(() {
          uploadStatus["${docType}_$side"] = true;
        });
        
        if (!alreadyUploadedDocs.contains(docType)) {
          final prefs = await SharedPreferences.getInstance();
          alreadyUploadedDocs.add(docType);
          await prefs.setStringList('uploadedDocTypes', alreadyUploadedDocs);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('${docType.toUpperCase()} $side uploaded'),
                ],
              ),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        throw Exception("Upload failed: ${res.body}");
      }
    } catch (e) {
      setState(() {
        uploadStatus["${docType}_$side"] = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => isUploading = false);
    }
  }

  Future<void> uploadProfilePhoto() async {
    if (profilePhoto == null) return;
    
    setState(() => isUploading = true);
    
    try {
      final uri = Uri.parse("$backendUrl/api/driver/uploadProfilePhoto");
      final request = http.MultipartRequest("POST", uri);
      
      final token = await getToken();
      if (token == null) throw Exception("Authentication failed");
      
      request.headers['Authorization'] = 'Bearer $token';
      
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
      
      if (response.statusCode == 200) {
        print("✅ Profile photo uploaded successfully");
      } else {
        final res = await http.Response.fromStream(response);
        throw Exception("Upload failed: ${res.body}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload profile photo: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => isUploading = false);
    }
  }

  // ✅ NEW: Build vehicle details form
  Widget _buildVehicleDetailsForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.badge,
              size: 80,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Driver Details",
            style: AppTextStyles.heading2,
          ),
          const SizedBox(height: 8),
          Text(
            "Please enter your name and vehicle number",
            style: AppTextStyles.body2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Name Input
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: TextFormField(
              controller: _nameController,
              style: AppTextStyles.body1,
              decoration: InputDecoration(
                labelText: "Full Name",
                labelStyle: AppTextStyles.body2.copyWith(
                  color: AppColors.primary,
                ),
                hintText: "Enter your full name",
                hintStyle: AppTextStyles.body2,
                prefixIcon: Container(
                  margin: EdgeInsets.all(12),
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person, color: AppColors.primary, size: 20),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(20),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                if (value.trim().length < 3) {
                  return 'Name must be at least 3 characters';
                }
                return null;
              },
            ),
          ),

          const SizedBox(height: 20),

          // Vehicle Number Input
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: TextFormField(
              controller: _vehicleNumberController,
              style: AppTextStyles.body1.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
              decoration: InputDecoration(
                labelText: "Vehicle Number",
                labelStyle: AppTextStyles.body2.copyWith(
                  color: AppColors.primary,
                ),
                hintText: "e.g., KA01AB1234",
                hintStyle: AppTextStyles.body2,
                prefixIcon: Container(
                  margin: EdgeInsets.all(12),
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.directions_car, color: AppColors.primary, size: 20),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(20),
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter vehicle number';
                }
                // Basic validation for Indian vehicle numbers
                final regex = RegExp(r'^[A-Z]{2}\d{2}[A-Z]{0,2}\d{4}$');
                if (!regex.hasMatch(value.trim().toUpperCase())) {
                  return 'Invalid format (e.g., KA01AB1234)';
                }
                return null;
              },
            ),
          ),

          const SizedBox(height: 32),

          // Info box
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "This information will be shown to customers during rides",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isUploading ? null : _saveDriverDetails,
              icon: isUploading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                      ),
                    )
                  : Icon(Icons.check_circle),
              label: Text(
                isUploading ? "Saving..." : "Save & Continue",
                style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDocBox(String docType) {
    final frontFile = uploadedDocs["${docType}_front"];
    final backFile = uploadedDocs["${docType}_back"];
    final frontUploaded = uploadStatus["${docType}_front"] ?? false;
    final backUploaded = uploadStatus["${docType}_back"] ?? false;
    final isAlreadyUploaded = alreadyUploadedDocs.contains(docType);

    Widget buildSide(String side, File? file, bool uploaded) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: uploaded 
                ? AppColors.success 
                : AppColors.divider,
            width: uploaded ? 2 : 1,
          ),
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
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: uploaded
                        ? AppColors.success.withOpacity(0.1)
                        : AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    side == 'front' ? Icons.credit_card : Icons.flip_to_back,
                    color: uploaded ? AppColors.success : AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${_getDocDisplayName(docType)}",
                        style: AppTextStyles.body1.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        side.toUpperCase(),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (uploaded)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: AppColors.onPrimary,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Uploaded",
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.onPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
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
                          uploaded ? Icons.check_circle_outline : Icons.upload_file,
                          size: 48,
                          color: uploaded 
                              ? AppColors.success
                              : AppColors.onSurfaceTertiary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          uploaded ? "Already uploaded" : "No file selected",
                          style: AppTextStyles.body2.copyWith(
                            color: uploaded ? AppColors.success : null,
                          ),
                        ),
                      ],
                    ),
                  ),
            if (!uploaded) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isUploading ? null : () => pickAndUpload(docType, side, fromCamera: false),
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
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isUploading ? null : () => pickAndUpload(docType, side, fromCamera: true),
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
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSide("front", frontFile, frontUploaded),
        buildSide("back", backFile, backUploaded),
      ],
    );
  }

  String _getDocDisplayName(String docType) {
    final displayNames = {
      'license': 'Driving License',
      'aadhaar': 'Aadhaar Card',
      'pan': 'PAN Card',
      'rc': 'Vehicle RC',
      'permit': 'Auto Permit',
      'insurance': 'Insurance',
      'fitnessCertificate': 'Fitness Certificate',
    };
    return displayNames[docType] ?? docType.toUpperCase();
  }

  bool _canProceedToNext() {
    if (vehicleType == null || currentStep >= requiredDocs.length + 1) {
      return false;
    }
    
    // Step 0 is vehicle details - must be saved
    if (currentStep == 0) {
      return _detailsSaved;
    }
    
    // Step 1+ are documents
    final docIndex = currentStep - 1;
    if (docIndex < 0 || docIndex >= requiredDocs.length) {
      return false;
    }
    
    final docType = requiredDocs[docIndex];
    
    if (alreadyUploadedDocs.contains(docType)) {
      return true;
    }
    
    final frontUploaded = uploadStatus["${docType}_front"] ?? false;
    final backUploaded = uploadStatus["${docType}_back"] ?? false;
    
    return frontUploaded && backUploaded;
  }

  Widget buildStepContent() {
    if (vehicleType == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.directions_car,
              size: 80,
              color: AppColors.primary,
            ),
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
    } 
    // ✅ Step 0: Vehicle Details (Name + Number)
    else if (currentStep == 0) {
      return _buildVehicleDetailsForm();
    }
    // Step 1+: Documents
    else if (currentStep <= requiredDocs.length) {
      final docIndex = currentStep - 1;
      final docType = requiredDocs[docIndex];
      final totalDocs = requiredDocs.length;
      final canProceed = _canProceedToNext();
      final isAlreadyUploaded = alreadyUploadedDocs.contains(docType);
      final remainingDocs = requiredDocs.where((doc) => !alreadyUploadedDocs.contains(doc)).length;
      
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.1),
                  AppColors.primary.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Document $currentStep of $totalDocs",
                          style: AppTextStyles.heading3.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          remainingDocs > 0 
                              ? "$remainingDocs remaining"
                              : "All documents uploaded!",
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        "${((alreadyUploadedDocs.length / totalDocs) * 100).toStringAsFixed(0)}%",
                        style: AppTextStyles.body1.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: alreadyUploadedDocs.length / totalDocs,
                    backgroundColor: AppColors.surface,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          buildDocBox(docType),
          
          Row(
            children: [
              if (currentStep > 0) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => currentStep--),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(
                      "Previous",
                      style: AppTextStyles.button,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: canProceed ? () => setState(() => currentStep++) : null,
                  icon: Icon(
                    isAlreadyUploaded ? Icons.skip_next : Icons.arrow_forward,
                  ),
                  label: Text(
                    isAlreadyUploaded 
                        ? "Skip"
                        : currentStep == totalDocs 
                            ? "Continue" 
                            : "Next",
                    style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canProceed ? AppColors.success : AppColors.onSurfaceSecondary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: canProceed ? 2 : 0,
                  ),
                ),
              ),
            ],
          ),
          if (!canProceed && !isAlreadyUploaded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Please upload both front and back sides to proceed",
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    } else {
      // Profile photo step
      return Column(
        children: [
          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_circle,
              size: 80,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Almost Done!",
            style: AppTextStyles.heading2,
          ),
          const SizedBox(height: 8),
          Text(
            "Upload a profile photo (Optional)",
            style: AppTextStyles.body2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withOpacity(0.1),
                  AppColors.success.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.success.withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.success, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "All Documents Uploaded",
                        style: AppTextStyles.heading3.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem(
                        Icons.description,
                        "${requiredDocs.length}",
                        "Documents",
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: AppColors.divider,
                      ),
                      _buildSummaryItem(
                        Icons.check_circle_outline,
                        "100%",
                        "Complete",
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: AppColors.onSurface.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
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
                    onPressed: isUploading ? null : () async {
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 85,
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
                      elevation: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isUploading ? null : () async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => Dialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: AppColors.primary),
                                const SizedBox(height: 16),
                                Text(
                                  "Finalizing registration...",
                                  style: AppTextStyles.body1,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  "Please wait",
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );

                      if (profilePhoto != null) {
                        await uploadProfilePhoto();
                      }

                      await Future.delayed(const Duration(milliseconds: 500));

                      if (mounted) Navigator.pop(context);

                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DocumentsReviewPage(
                              driverId: widget.driverId,
                            ),
                          ),
                        );
                      }
                    },
                    icon: isUploading 
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                            ),
                          )
                        : const Icon(Icons.check_circle),
                    label: Text(
                      "Finish & Review Documents",
                      style: AppTextStyles.button.copyWith(color: AppColors.onPrimary),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
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

  Widget _buildSummaryItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppColors.success, size: 24),
        SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.heading3.copyWith(
            color: AppColors.success,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.caption,
        ),
      ],
    );
  }

  Widget _buildVehicleTypeButton(String type) {
    IconData icon;
    String label;
    String description;
    
    switch (type) {
      case 'bike':
        icon = Icons.two_wheeler;
        label = 'BIKE';
        description = 'Two-wheeler vehicle';
        break;
      case 'auto':
        icon = Icons.airport_shuttle;
        label = 'AUTO';
        description = 'Auto rickshaw';
        break;
      case 'car':
        icon = Icons.directions_car;
        label = 'CAR';
        description = 'Four-wheeler vehicle';
        break;
      default:
        icon = Icons.help;
        label = type.toUpperCase();
        description = '';
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final token = await getToken();
            if (token == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Authentication error. Please login again.'),
                  backgroundColor: AppColors.error,
                ),
              );
              return;
            }

            final uri = Uri.parse("$backendUrl/api/driver/setVehicleType");
            try {
              final res = await http.post(
                uri,
                headers: {
                  "Content-Type": "application/json",
                  "Authorization": "Bearer $token"
                },
                body: jsonEncode({"vehicleType": type}),
              );

              if (res.statusCode == 200) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString("vehicleType", type);
                
                setState(() {
                  vehicleType = type;
                  requiredDocs = getRequiredDocs(type);
                  currentStep = 0; // Start at vehicle details form
                });
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Vehicle type set to ${type.toUpperCase()}'),
                      ],
                    ),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to set vehicle type'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.2),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 32, color: AppColors.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.heading3,
                      ),
                      SizedBox(height: 4),
                      Text(
                        description,
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (vehicleType != null && currentStep > 0) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                "Exit Registration?",
                style: AppTextStyles.heading3,
              ),
              content: Text(
                "Your progress will be saved. You can continue from where you left off.",
                style: AppTextStyles.body2,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    "Cancel",
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.onSurfaceSecondary,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    "Exit",
                    style: AppTextStyles.button.copyWith(
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
          return shouldPop ?? false;
        }
        return true;
      },
      child: Scaffold(
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
      ),
    );
  }
}