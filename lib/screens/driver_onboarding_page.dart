import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'driver_details_page.dart';

class DriverOnboardingPage extends StatefulWidget {
  final String driverId;
  const DriverOnboardingPage({super.key, required this.driverId});
  @override
  State<DriverOnboardingPage> createState() => _DriverOnboardingPageState();
}

class _DriverOnboardingPageState extends State<DriverOnboardingPage> {
  int currentStep = 1;
  String? selectedVehicle;
  String selectedCity = "Hyderabad";

  final cities = ["Hyderabad", "Bangalore", "Chennai", "Mumbai"];

  void goToNextStep() {
    if (currentStep < 3) {
      setState(() => currentStep++);
    }
  }

  void goToPreviousStep() {
    if (currentStep > 1) {
      setState(() => currentStep--);
    }
  }

  Widget _stepTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Text(
        title,
        style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Driver Onboarding",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _buildStepContent(),
              ),
            ),
            _buildBottomNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (currentStep) {
      case 1:
        return SingleChildScrollView(
          key: const ValueKey(1),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stepTitle("Select your vehicle"),
              _buildVehicleCard("Bike", "Bike Taxi & Delivery", "🚲"),
              _buildVehicleCard("Auto", "Auto Lite, etc", "🛺"),
              _buildVehicleCard("Cab", "Airport Cabs, etc", "🚗"),
            ],
          ),
        );

      case 2:
        return SingleChildScrollView(
          key: const ValueKey(2),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stepTitle("Which city do you want to ride?"),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.location_pin, color: Colors.indigo),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedCity,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: cities
                          .map(
                            (city) => DropdownMenuItem(
                              value: city,
                              child: Text(city),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => selectedCity = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case 3:
        Future.microtask(() {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDetailsPage(
                vehicleType: selectedVehicle ?? "Bike",
                city: selectedCity,
                driverId: widget.driverId,
              ),
            ),
          );
        });
        return const Center(child: CircularProgressIndicator());
      default:
        return const SizedBox();
    }
  }

  Widget _buildBottomNavigation() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (currentStep > 1)
            TextButton(
              onPressed: goToPreviousStep,
              child: const Text("← Back"),
            ),
          ElevatedButton(
            onPressed: currentStep == 1 && selectedVehicle == null
                ? null
                : () {
                    if (currentStep < 3) {
                      goToNextStep();
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              currentStep == 3 ? "Submit" : "Next",
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(String title, String desc, String emoji) {
    final selected = selectedVehicle == title;

    return GestureDetector(
      onTap: () {
        setState(() => selectedVehicle = title);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? Colors.indigo.shade50 : Colors.white,
          border: Border.all(
            color: selected ? Colors.indigo : Colors.grey.shade300,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const Spacer(),
            Radio<String>(
              value: title,
              groupValue: selectedVehicle,
              onChanged: (value) {
                setState(() => selectedVehicle = value);
              },
              activeColor: Colors.indigo,
            ),
          ],
        ),
      ),
    );
  }
}
