import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'leave_screen.dart';
import 'payslip_screen.dart';
import 'expenses_screen.dart';
import 'more_screen.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  @override
  void initState() {
    super.initState();

    // Ask notification permission on screen load (Android 13+)
    _requestNotificationPermission();

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
      fetchStatus();
    });

  }
  StreamSubscription<Position>? positionStream;

  Future<void> _requestNotificationPermission() async {
    if (await Permission.notification.isGranted) return;

    var status = await Permission.notification.request();

    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Notification Permission Required"),
            content: const Text(
              "Please enable notification permission from app settings to allow check-in notifications.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  openAppSettings();
                  Navigator.pop(context);
                },
                child: const Text("Open Settings"),
              ),
            ],
          ),
        );
      }
    }
  }
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  bool hasShownOutOfBoundsNotification = false;

  Future<void> initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> showOutOfLocationNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'location_channel',
      'Location Alerts',
      channelDescription: 'Alerts when user goes out of bounds',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Location Alert',
      'You are out of the allowed location!',
      platformChannelSpecifics,
      payload: 'out_of_location',
    );
  }

  Future<void> _startLocationMonitoring() async {
    if (!await Permission.locationAlways.isGranted) {
      await Permission.locationAlways.request();
    }

    await initializeNotifications();

    const double officeLatitude = 17.502635;
    const double officeLongitude = 78.352666;
    const double radiusInMeters = 100;

    final service = FlutterBackgroundService();

    await service.startService();
    service.invoke("setAsForeground");

    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    ).listen((position) async {
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        officeLatitude,
        officeLongitude,
      );

      print('Current Distance from office: $distance meters');

      if (distance > radiusInMeters) {
        if (!hasShownOutOfBoundsNotification) {
          await showOutOfLocationNotification();
          hasShownOutOfBoundsNotification = true;
        }
      } else {
        hasShownOutOfBoundsNotification = false; // Reset if back in range
      }
    });
  }

  void _stopLocationMonitoring() {
    positionStream?.cancel();
  }

  Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: true,
        notificationChannelId: 'location_channel',
        initialNotificationTitle: 'Tracking Location',
        initialNotificationContent: 'Background service is running',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  void onStart(ServiceInstance service) {
    DartPluginRegistrant.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.on("setAsForeground").listen((event) {
        service.setAsForegroundService();
      });

      service.on("stopService").listen((event) {
        service.stopSelf();
      });
    }
  }

  @pragma('vm:entry-point')
  Future<bool> onIosBackground(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  @override
  void dispose() {
    clockTimer?.cancel();
    workingTimer?.cancel();
    positionStream?.cancel();
    super.dispose();
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

  Future<void> handleCheckIn() async {
    if (await Permission.notification.isDenied ||
        await Permission.notification.isPermanentlyDenied) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Notification permission is required for background tracking")),
        );
        return;
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final service = FlutterBackgroundService();
    await service.startService();
    _startLocationMonitoring();

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

    final service = FlutterBackgroundService();
    service.invoke("stopService");
    _stopLocationMonitoring();

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

  void updateTime() {
    final now = DateTime.now();
    setState(() {
      currentTime = DateFormat('hh:mm:ss a').format(now);
    });
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
