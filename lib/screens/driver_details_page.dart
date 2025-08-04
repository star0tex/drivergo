import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import 'driver_dashboard_page.dart';

const String backendUrl = "http://192.168.210.12:5002";

class DriverDetailsPage extends StatefulWidget {
  final String vehicleType;
  final String city;
  final String? driverId;

  const DriverDetailsPage({
    super.key,
    required this.vehicleType,
    required this.city,
    required this.driverId,
  });

  @override
  State<DriverDetailsPage> createState() => _DriverDetailsPageState();
}

class _DriverDetailsPageState extends State<DriverDetailsPage> {
  int currentStep = 0;
  String? _driverId;

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final vehicleController = TextEditingController();
  final dlNumberController = TextEditingController();
  final rcNumberController = TextEditingController();
  final aadhaarNumberController = TextEditingController();

  File? dlImage, rcImage, aadhaarImage;
  List<String> uploadedFiles = [];

  @override
  void initState() {
    super.initState();
    _driverId = widget.driverId;
    _addCapitalization(nameController);
    _addCapitalization(vehicleController);
    _addCapitalization(dlNumberController);
    _addCapitalization(rcNumberController);
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    vehicleController.dispose();
    dlNumberController.dispose();
    rcNumberController.dispose();
    aadhaarNumberController.dispose();
    super.dispose();
  }

  void _addCapitalization(TextEditingController controller) {
    controller.addListener(() {
      final text = controller.text.toUpperCase();
      if (controller.text != text) {
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    });
  }

  void nextStep() {
    if (currentStep < 4) {
      setState(() => currentStep++);
    }
  }

  Future<void> pickImage(String type) async {
    if (_driverId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Driver ID is missing!")));
      return;
    }

    final permission = await Permission.photos.request();
    if (!permission.isGranted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);
    setState(() {
      if (type == 'DL') dlImage = file;
      if (type == 'RC') rcImage = file;
      if (type == 'Aadhaar') aadhaarImage = file;
    });

    final uri = Uri.parse("$backendUrl/api/ocr/extract-text");
    final request = http.MultipartRequest("POST", uri);
    request.files.add(await http.MultipartFile.fromPath("document", file.path));
    request.fields['driverId'] = _driverId!;
    request.fields['documentType'] = type;

    try {
      final response = await request.send();
      final res = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        final result = jsonDecode(res.body);
        uploadedFiles.add(result['filePath'].toString());
      } else {
        print("❌ OCR failed: ${res.body}");
      }
    } catch (e) {
      print("❌ Error uploading image: $e");
    }
  }

  Future<void> submitDriver() async {
    final uri = Uri.parse("$backendUrl/api/driver/register");
    final body = jsonEncode({
      "driverId": _driverId,
      "name": nameController.text.trim(),
      "phone": phoneController.text.trim(),
      "vehicleNumber": vehicleController.text.trim(),
      "dlNumber": dlNumberController.text.trim(),
      "rcNumber": rcNumberController.text.trim(),
      "aadhaarNumber": aadhaarNumberController.text.trim(),
      "vehicleType": widget.vehicleType,
      "city": widget.city,
    });

    try {
      final res = await http.post(
        uri,
        body: body,
        headers: {'Content-Type': 'application/json'},
      );
      if (res.statusCode == 201) {
        final data = jsonDecode(res.body);
        setState(() {
          _driverId = data['driverId'];
        });
        nextStep();
      } else {
        print("❌ Failed to register: ${res.body}");
      }
    } catch (e) {
      print("❌ Network error: $e");
    }
  }

  Widget buildInput(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label.toUpperCase(),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Colors.grey.shade100,
        ),
      ),
    );
  }

  Widget buildImagePicker(String label, File? image, VoidCallback onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (image != null)
          Container(
            height: 150,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(10),
              image: DecorationImage(
                image: FileImage(image),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ElevatedButton(onPressed: onPick, child: Text("Upload $label")),
      ],
    );
  }

  Widget buildStepContent() {
    switch (currentStep) {
      case 0:
        return Column(
          children: [
            buildInput("Full Name", nameController),
            buildInput("Phone Number", phoneController),
            buildInput("Vehicle Number", vehicleController),
            ElevatedButton(
              onPressed: submitDriver,
              child: const Text("Register & Continue"),
            ),
          ],
        );
      case 1:
        return Column(
          children: [
            buildInput("DL Number", dlNumberController),
            buildImagePicker("Driving License", dlImage, () => pickImage("DL")),
            ElevatedButton(onPressed: nextStep, child: const Text("Next")),
          ],
        );
      case 2:
        return Column(
          children: [
            buildInput("RC Number", rcNumberController),
            buildImagePicker("RC Book", rcImage, () => pickImage("RC")),
            ElevatedButton(onPressed: nextStep, child: const Text("Next")),
          ],
        );
      case 3:
        return Column(
          children: [
            buildInput("Aadhaar Number", aadhaarNumberController),
            buildImagePicker(
              "Aadhaar",
              aadhaarImage,
              () => pickImage("Aadhaar"),
            ),
            ElevatedButton(onPressed: nextStep, child: const Text("Finish")),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "✅ Registration Submitted",
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 10),
            const Text(
              "📄 Uploaded Files:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (var path in uploadedFiles)
              Text(
                "- ${path.split('/').last}",
                style: const TextStyle(color: Colors.grey),
              ),
            const SizedBox(height: 20),
            const Text(
              "⏳ Status: Pending",
              style: TextStyle(color: Colors.orange, fontSize: 16),
            ),
            const SizedBox(height: 30),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  if (_driverId != null) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DriverDashboardPage(
                          driverId: _driverId!,
                          vehicleType: widget.vehicleType,
                        ),
                      ),
                    );
                  }
                },
                child: const Text("GO TO DASHBOARD"),
              ),
            ),
          ],
        );
      default:
        return const Text("Unknown Step");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Driver Onboarding - Step ${currentStep + 1}"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: buildStepContent(),
      ),
    );
  }
}
