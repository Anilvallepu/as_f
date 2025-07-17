import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'leave_screen.dart';
import 'payslip_screen.dart';
import 'expenses_screen.dart';
import 'more_screen.dart';

class CheckInOutScreen extends StatefulWidget {
  final String empName;
  final String empId;
  final String authToken;

  const CheckInOutScreen({
    super.key,
    required this.empName,
    required this.empId,
    required this.authToken,
  });

  @override
  State<CheckInOutScreen> createState() => _CheckInOutScreenState();
}

class _CheckInOutScreenState extends State<CheckInOutScreen> {
  late Timer clockTimer;
  Timer? workingTimer;

  String currentTime = '';
  String checkInTime = '--:--:--';
  String checkOutTime = '--:--:--';
  String totalWorkingHours = "00:00:00";

  bool isAllowedToCheckIn = true;
  bool isAllowedToCheckOut = false;
  bool isCheckedIn = false;

  Duration workingDuration = Duration.zero;
  DateTime? sessionStart;

  @override
  void initState() {
    super.initState();
    updateTime();
    clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => updateTime());

    _loadCheckInState().then((wasCheckedIn) {
      if (wasCheckedIn) {
        isCheckedIn = true;
        isAllowedToCheckIn = false;
        isAllowedToCheckOut = true;
      } else {
        isCheckedIn = false;
        isAllowedToCheckIn = true;
        isAllowedToCheckOut = false;
      }
      setState(() {});
      fetchStatus(); // Fetch from server after local UI is ready
    });
  }

  @override
  void dispose() {
    clockTimer.cancel();
    workingTimer?.cancel();
    super.dispose();
  }

  void updateTime() {
    final now = DateTime.now();
    setState(() {
      currentTime = DateFormat('hh:mm:ss a').format(now);
    });
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception("Location services are disabled.");

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception("Location permission denied.");
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception("Location permanently denied.");
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> fetchStatus() async {
    try {
      final position = await _getCurrentLocation();
      final response = await http.post(
        Uri.parse("https://hrm.eltrive.com/Api/status"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.authToken}",
        },
        body: jsonEncode({
          "emp_id": widget.empId,
          "latitude": position.latitude.toString(),
          "longitude": position.longitude.toString(),
          "timestamp": DateTime.now().toUtc().toIso8601String(),
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        isCheckedIn = data['current_status'] == 'checked_in';
        isAllowedToCheckIn = data['is_allowed_to_check_in'] == "true";
        isAllowedToCheckOut = data['is_allowed_to_check_out'] == "true";

        await _saveCheckInState(isCheckedIn);

        final rawWorkingTime = data['cumulative_working_hours'] ?? "00:00:00";
        final lastCheckInTimeStr = data['last_check_in_time'];
        workingDuration = _parseDuration(rawWorkingTime);

        if (isCheckedIn && lastCheckInTimeStr != null) {
          final lastCheckIn = DateTime.parse(lastCheckInTimeStr).toLocal();
          sessionStart = lastCheckIn;
          final elapsed = DateTime.now().difference(lastCheckIn);
          workingDuration += elapsed;
          startWorkingTimer();
        } else {
          stopWorkingTimer();
        }

        setState(() {
          totalWorkingHours = _formatDuration(workingDuration);
          checkInTime = lastCheckInTimeStr != null
              ? _formatToTime(lastCheckInTimeStr)
              : "--:--:--";
          checkOutTime = data['last_check_out_time'] != null
              ? _formatToTime(data['last_check_out_time'])
              : "--:--:--";
        });
      }
    } catch (e) {
      print("Error fetching status: $e");
    }
  }

  Future<void> handleCheckIn() async {
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      final position = await _getCurrentLocation();
      final response = await http.post(
        Uri.parse("https://hrm.eltrive.com/Api/checkin"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "auth_token": widget.authToken,
          "emp_id": widget.empId,
          "latitude": position.latitude.toString(),
          "longitude": position.longitude.toString(),
          "timestamp": now,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        final cumTimeStr = data['cumulative_working_hours'] ?? "00:00:00";
        workingDuration = _parseDuration(cumTimeStr);

        sessionStart = DateTime.now();
        checkInTime = DateFormat('hh:mm:ss a').format(sessionStart!);

        isCheckedIn = true;
        isAllowedToCheckIn = false;
        isAllowedToCheckOut = true;
        await _saveCheckInState(true);

        setState(() {
          totalWorkingHours = _formatDuration(workingDuration);
        });

        startWorkingTimer();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Check-In Successful")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Check-In Failed: ${data['message']}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Check-In Error: $e")),
      );
    }
  }

  Future<void> handleCheckOut() async {
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      final position = await _getCurrentLocation();
      final response = await http.post(
        Uri.parse("https://hrm.eltrive.com/Api/checkout"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "auth_token": widget.authToken,
          "emp_id": widget.empId,
          "latitude": position.latitude.toString(),
          "longitude": position.longitude.toString(),
          "timestamp": now,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        stopWorkingTimer();
        final nowLocal = DateTime.now();

        setState(() {
          checkOutTime = DateFormat('hh:mm:ss a').format(nowLocal);
          totalWorkingHours = _formatDuration(workingDuration);
          isCheckedIn = false;
          isAllowedToCheckIn = true;
          isAllowedToCheckOut = false;
        });

        await _saveCheckInState(false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Check-Out Successful")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Check-Out Failed: ${data['message']}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Check-Out Error: $e")),
      );
    }
  }

  void startWorkingTimer() {
    workingTimer?.cancel();
    workingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        workingDuration += const Duration(seconds: 1);
        totalWorkingHours = _formatDuration(workingDuration);
      });
    });
  }

  void stopWorkingTimer() {
    workingTimer?.cancel();
    workingTimer = null;
  }

  Future<void> _saveCheckInState(bool isCheckedIn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_checked_in', isCheckedIn);
  }

  Future<bool> _loadCheckInState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_checked_in') ?? false;
  }

  Duration _parseDuration(String timeStr) {
    try {
      final parts = timeStr.split(':').map(int.parse).toList();
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    } catch (_) {
      return Duration.zero;
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  String _formatToTime(String isoTime) {
    try {
      final parsed = DateTime.parse(isoTime).toLocal();
      return DateFormat('hh:mm:ss a').format(parsed);
    } catch (_) {
      return "--:--:--";
    }
  }

  String _getGreetingMessage() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: Colors.greenAccent,
        unselectedItemColor: Colors.white70,
        showUnselectedLabels: true,
        currentIndex: _selectedIndex,
        onTap: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/attndance_logo.png'),
              size: 24,
              color: _selectedIndex == 0 ? Colors.greenAccent : Colors.white70,
            ),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/leave_logo.png'),
              size: 24,
              color: _selectedIndex == 1 ? Colors.greenAccent : Colors.white70,
            ),
            label: 'Leaves',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/payslip_icon.png'),
              size: 24,
              color: _selectedIndex == 2 ? Colors.greenAccent : Colors.white70,
            ),
            label: 'Payslip',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/approval_logos.png'),
              size: 24,
              color: _selectedIndex == 3 ? Colors.greenAccent : Colors.white70,
            ),
            label: 'Expenses',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(
              AssetImage('assets/up_more.png'),
              size: 24,
              color: _selectedIndex == 4 ? Colors.greenAccent : Colors.white70,
            ),
            label: 'More',
          ),
        ],
      ),
      body: _getBodyWidget(_selectedIndex, today),
    );
  }

  Widget _getBodyWidget(int index, String today) {
    if (index == 0) {
      // Original check-in screen
      return Column(
        children: [
          const SizedBox(height: 20),
          Image.asset('assets/eltrive_plan.png', height: 60),
          const SizedBox(height: 10),

          // Greeting text
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: "${_getGreetingMessage()} : ",
                  style: const TextStyle(
                    color: Color(0xFF00FF00),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: widget.empName.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF00FF00),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          Text(currentTime, style: const TextStyle(fontSize: 32, color: Colors.white)),
          const SizedBox(height: 5),
          Text(today, style: const TextStyle(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 30),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: isAllowedToCheckIn ? handleCheckIn : null,
                    child: Opacity(
                      opacity: isAllowedToCheckIn ? 1.0 : 0.4,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1AEA24),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            const Text("In", style: TextStyle(color: Colors.black, fontSize: 20)),
                            const SizedBox(height: 8),
                            const Icon(Icons.login, size: 36, color: Colors.black),
                            const SizedBox(height: 10),
                            Text(checkInTime, style: const TextStyle(color: Colors.black, fontSize: 16)),
                            const Text("Check In", style: TextStyle(color: Colors.black, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: isAllowedToCheckOut ? handleCheckOut : null,
                    child: Opacity(
                      opacity: isAllowedToCheckOut ? 1.0 : 0.4,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            const Text("Out", style: TextStyle(color: Colors.white, fontSize: 20)),
                            const SizedBox(height: 8),
                            const Icon(Icons.logout, size: 36, color: Colors.white),
                            const SizedBox(height: 10),
                            Text(checkOutTime, style: const TextStyle(color: Colors.white, fontSize: 16)),
                            const Text("Check Out", style: TextStyle(color: Colors.white, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              "Today Working Time : $totalWorkingHours",
              style: const TextStyle(color: Colors.greenAccent, fontSize: 16),
            ),
          ),
        ],
      );
    }

    // Replace with real widgets/screens
    switch (index) {
      case 1:
        return LeaveScreen(
          empId: widget.empId,
          empName: widget.empName,
          authToken: widget.authToken,
        );
      case 2:
        return PayslipScreen(

        );
      case 3:
        return ExpensesScreen(

        );
      case 4:
        return MoreScreen(

        );
      default:
        return Container();
    }

  }

}
