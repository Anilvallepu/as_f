import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LeaveScreen extends StatefulWidget {
  final String authToken;
  final String empId;
  final String empName;

  const LeaveScreen({
    Key? key,
    required this.authToken,
    required this.empId,
    required this.empName,
  }) : super(key: key);

  @override
  _LeaveScreenState createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  String? selectedLeaveTypeId;
  bool _isSubmitting = false;

  final Set<String> _submittedLeaves = {};

  final List<Map<String, String>> leaveTypes = [
    {"id": "1", "label": "Casual Leave"},
    {"id": "2", "label": "Comp Off Leave"},
    {"id": "3", "label": "Earned Leave"},
  ];

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    DateTime initialDate = DateTime.now();
    if (controller.text.isNotEmpty) {
      initialDate = DateTime.tryParse(controller.text) ?? DateTime.now();
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(), // 👈 prevents selecting past dates
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      controller.text = picked.toIso8601String().split('T')[0]; // Format: YYYY-MM-DD
    }
  }



  Future<void> _submitLeave() async {
    if (_isSubmitting) return;

    if (_fromDateController.text.isEmpty ||
        _toDateController.text.isEmpty ||
        selectedLeaveTypeId == null ||
        _reasonController.text.isEmpty) {
      _showDialog("Error", "Please fill all fields.");
      return;
    }

    DateTime fromDate = DateTime.parse(_fromDateController.text);
    DateTime toDate = DateTime.parse(_toDateController.text);

    if (fromDate.isAfter(toDate)) {
      _showDialog("Error", "From date cannot be after To date.");
      return;
    }
    if (fromDate.isBefore(DateTime.now().subtract(const Duration(days: 1))) ||
        toDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      _showDialog("Invalid Date", "You cannot apply for leave in the past.");
      return;
    }
    final String leaveKey =
        '${widget.empId}_${_fromDateController.text}_${_toDateController.text}_$selectedLeaveTypeId';

    if (_submittedLeaves.contains(leaveKey)) {
      _showDialog("Duplicate", "Leave already submitted for these dates.");
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final url = Uri.parse('https://hrm.eltrive.com/api/leaveapply');

    final body = {
      "auth_token": widget.authToken,
      "emp_id": widget.empId,
      "leave_type_id": selectedLeaveTypeId!,
      "from_date": _fromDateController.text,
      "to_date": _toDateController.text,
      "reason": _reasonController.text,
    };

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      final result = jsonDecode(response.body);

      if (result["status"] == "success") {
        _submittedLeaves.add(leaveKey);
        _showDialog("Success", result["message"] ?? "Leave applied successfully");
      } else {
        _showDialog("Failed", result["message"] ?? "Something went wrong");
      }
    } catch (e) {
      _showDialog("Error", "Could not apply leave. Try again later.");
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _showDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          ElevatedButton(
            child: const Text("OK"),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fromDateController.dispose();
    _toDateController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Apply Leave"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.center,
              child: Text(
                "Hello, ${widget.empName}",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _fromDateController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: "From Date",
                suffixIcon: Icon(Icons.calendar_today),
              ),
              onTap: () => _selectDate(context, _fromDateController),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _toDateController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: "To Date",
                suffixIcon: Icon(Icons.calendar_today),
              ),
              onTap: () => _selectDate(context, _toDateController),
            ),
            const SizedBox(height: 16),
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
                  selectedLeaveTypeId = value;
                });
              },
              value: selectedLeaveTypeId,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: "Reason",
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitLeave,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                  "Submit Leave",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.blue,
                  elevation: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
