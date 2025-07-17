import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PayslipScreen extends StatelessWidget {
  final Uri _url = Uri.parse('https://hrm.eltrive.com/salary');

  void _launchURL() async {
    if (!await launchUrl(_url, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $_url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Payslip")),
      body: Center(
        child: ElevatedButton(
          onPressed: _launchURL,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          child: const Text('Open Payslip Portal'),
        ),
      ),
    );
  }
}
