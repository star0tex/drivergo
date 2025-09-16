import 'dart:convert';
import 'dart:io';
import 'package:drivergoo/screens/documents_review_page.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart'; // ADD THIS
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'driver_dashboard_page.dart'; // ✅ Add this (use correct path if needed)

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

  final String backendUrl = "http://192.168.1.12:5002";

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
    return "application/octet-stream"; // fallback
  }

  final mimeType = getMimeType(file.path);
  request.files.add(
    await http.MultipartFile.fromPath(
      "document",
      file.path,
      contentType: MediaType.parse(mimeType),
    ),
  );

  request.fields['docType'] = docType;      // ✅ just license, aadhaar, etc.
request.fields['docSide'] = side;         // ✅ send separately
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
      return "image/jpeg"; // Fallback default
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
    return Column(
      children: [
        Text("$docType ($side)", style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        file != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(file, height: 160, width: double.infinity, fit: BoxFit.cover),
              )
            : Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Text("No file selected")),
              ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
              onPressed: () => pickAndUpload(docType, side, fromCamera: false),
              child: const Text("Upload (Gallery)"),
            ),
            ElevatedButton(
              onPressed: () => pickAndUpload(docType, side, fromCamera: true),
              child: const Text("Take Photo"),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
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
        children: [
          const Text(
            "Select your vehicle type",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          for (var type in ['bike', 'auto', 'car'])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: ElevatedButton(
                onPressed: () {
                  setState(() => vehicleType = type);
                  print("Current vehicle type: $vehicleType"); // 🔍 Add here
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.blue.shade800,
                ),
                child: Text(type.toUpperCase()),
              ),
            ),
        ],
      );
    } else if (currentStep < getRequiredDocs(vehicleType!).length) {
      final docType = getRequiredDocs(vehicleType!)[currentStep];
      return Column(
        children: [
          buildDocBox(docType),
          ElevatedButton(
            onPressed: () => setState(() => currentStep++),
            child: const Text("Next"),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          const Text(
            "Upload Profile Photo",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          profilePhoto != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    profilePhoto!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                )
              : Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(child: Text("No photo selected")),
                ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              final picked = await picker.pickImage(
                source: ImageSource.gallery,
              );
              if (picked != null)
                setState(() => profilePhoto = File(picked.path));
            },
            child: const Text("Select Photo"),
          ),
          const SizedBox(height: 8),
        ElevatedButton(
  onPressed: () async {
    await uploadProfilePhoto();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DocumentsReviewPage(
        ),
      ),
    );
  },
  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
  child: const Text("Finish"),
),

          const SizedBox(height: 8),
     
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Registration"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: buildStepContent(),
      ),
    );
  }
}
