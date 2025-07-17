import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LeaveScreen extends StatefulWidget {
  final String empId;
  final String empName;
  final String authToken;

  const LeaveScreen({
    Key? key,
    required this.empId,
    required this.empName,
    required this.authToken,
  }) : super(key: key);

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  String? selectedLeaveType;

  final List<Map<String, String>> leaveTypes = [
    {"id": "1", "label": "Sick Leave"},
    {"id": "2", "label": "Casual Leave"},
    {"id": "3", "label": "Earned Leave"},
  ];

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2026),
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _submitLeave() async {
    if (_fromDateController.text.isEmpty ||
        _toDateController.text.isEmpty ||
        selectedLeaveType == null ||
        _reasonController.text.isEmpty) {
      _showDialog("Error", "Please fill all fields.");
      return;
    }

    final url = Uri.parse('https://hrm.eltrive.com/api/leaveapply');
    final body = {
      "auth_token": widget.authToken,
      "emp_id": widget.empId,
      "from_date": _fromDateController.text,
      "to_date": _toDateController.text,
      "leave_type": selectedLeaveType!,
      "reason": _reasonController.text,
    };

    try {
      final response = await http.post(url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body));

      final result = jsonDecode(response.body);

      if (result["status"] == "success") {
        _showDialog("Success", result["message"]);
      } else {
        _showDialog("Failed", result["message"] ?? "Something went wrong");
      }
    } catch (e) {
      _showDialog("Error", "Could not apply leave. Try again later.");
    }
  }

  void _showDialog(String title, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apply for Leave')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Hello, ${widget.empName}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: _fromDateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: "From Date",
                suffixIcon: const Icon(Icons.calendar_today),
              ),
              onTap: () => _selectDate(context, _fromDateController),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _toDateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: "To Date",
                suffixIcon: const Icon(Icons.calendar_today),
              ),
              onTap: () => _selectDate(context, _toDateController),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Leave Type"),
              items: leaveTypes.map((type) {
                return DropdownMenuItem(
                  value: type["id"],
                  child: Text(type["label"]!),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedLeaveType = value;
                });
              },
              value: selectedLeaveType,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(labelText: "Reason"),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitLeave,
              child: const Text("Apply Leave"),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(45)),
            )
          ],
        ),
      ),
    );
  }
}
