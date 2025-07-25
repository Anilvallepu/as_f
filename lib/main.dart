import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'check_in_out_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eltrive Login',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController userIdController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  bool isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    requestLocationPermission();
  }

  Future<void> requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await Geolocator.requestPermission();
    }
  }

  Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.id ?? "unknown_device_id";
  }

  Future<Position?> getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> login() async {
    final userId = userIdController.text.trim();
    final password = passwordController.text.trim();

    if (userId.isEmpty || password.isEmpty) {
      showSnackbar("Please enter both user ID and password");
      return;
    }

    setState(() => isLoading = true);

   try {
      String deviceId = await getDeviceId();
      Position? position = await getLocation();

      final latitude = position?.latitude.toString() ?? "0.0";
      final longitude = position?.longitude.toString() ?? "0.0";

      final response = await http.post(
        Uri.parse("https://hrm.eltrive.com/Api/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": userId,
          "password": password,
          "device_serial_number": deviceId,
          "latitude": latitude,
          "longitude": longitude,
        }),
      );

      print("Login Response (${response.statusCode}): ${response.body}");

      late Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body);
      } catch (e) {
        showSnackbar("Invalid server response");
        return;
      }

      if (response.statusCode == 200 && json['status'] == "success") {
        final empName = json['emp_name'] ?? "Employee";
        final empId = json['emp_id'] ?? "";
        final authToken = json['auth_token'] ?? "";

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CheckInOutScreen(
              empName: empName,
              empId: empId,
              authToken: authToken,
            ),
          ),
        );
      } else {
        final errorMessage = json['message'] ?? "Invalid credentials or login failed";
        showSnackbar(errorMessage);
      }
    } catch (e) {
      showSnackbar("Login error: $e");

    } finally {
      setState(() => isLoading = false);
    }
  }

  void showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white), // White text
        ),
        backgroundColor: Colors.red, // Optional: red background for error
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ListView(
          children: [
            const SizedBox(height: 60),
            Center(
              child: Image.asset(
                'assets/eltrive_plan.png',
                height: 100,
              ),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: userIdController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "User ID",
                labelStyle: const TextStyle(color: Color(0xFF00FF00)),
                filled: true,
                fillColor: Colors.black45,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                  const BorderSide(color: Color(0xFF00FF00), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: passwordController,
              obscureText: !isPasswordVisible,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Password",
                labelStyle: const TextStyle(color: Color(0xFF00FF00)),
                filled: true,
                fillColor: Colors.black45,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                  const BorderSide(color: Color(0xFF00FF00), width: 2),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    isPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: Colors.white70,
                  ),
                  onPressed: () {
                    setState(() => isPasswordVisible = !isPasswordVisible);
                  },
                ),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading ? null : login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF440099),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2)
                    : const Text("Login", style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
