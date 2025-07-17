import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class ExpensesScreen extends StatefulWidget {
  @override
  _ExpensesScreenState createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  File? _receiptImage;
  bool _loading = false;

  List<Map<String, dynamic>> _expenses = [];

  @override
  void initState() {
    super.initState();
    _fetchExpenses();
  }

  Future<void> _fetchExpenses() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('https://your.api/expenses'));
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        setState(() => _expenses = List<Map<String, dynamic>>.from(data));
      }
    } catch (e) {
      // Handle offline or error
    }
    setState(() => _loading = false);
  }

  Future<void> _pickReceipt() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _receiptImage = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final payload = {
      'amount': double.tryParse(_amountCtrl.text.trim()),
      'description': _descCtrl.text.trim(),
      'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
      if (_receiptImage != null)
        'receiptBase64': base64Encode(await _receiptImage!.readAsBytes()),
    };

    setState(() => _loading = true);

    final res = await http.post(
      Uri.parse('https://https://hrm.eltrive.com/api/expenses'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    setState(() => _loading = false);

    if (res.statusCode == 201) {
      _amountCtrl.clear();
      _descCtrl.clear();
      setState(() {
        _selectedDate = DateTime.now();
        _receiptImage = null;
      });
      await _fetchExpenses();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Expense submitted successfully')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit expense')),
      );
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Expenses')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                    v == null || v.isEmpty ? 'Required' : null,
                  ),
                  SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.notes),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                    v == null || v.isEmpty ? 'Required' : null,
                  ),
                  SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final dt = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (dt != null) {
                        setState(() => _selectedDate = dt);
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Select Date',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        DateFormat('yyyy-MM-dd').format(_selectedDate),
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(Icons.image),
                        label: Text('Pick Receipt'),
                        onPressed: _pickReceipt,
                      ),
                      SizedBox(width: 16),
                      if (_receiptImage != null)
                        Text(
                          '✓ Selected',
                          style: TextStyle(color: Colors.green),
                        ),
                    ],
                  ),
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: Text('Submit Expense'),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 30),
            Divider(),
            Text(
              'Submitted Expenses',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 10),
            if (_loading)
              Center(child: CircularProgressIndicator())
            else if (_expenses.isEmpty)
              Text('No expenses found.')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: _expenses.length,
                itemBuilder: (_, i) {
                  final e = _expenses[i];
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      title: Text('₹ ${e['amount']}'),
                      subtitle: Text(e['description']),
                      trailing: Text(e['date']),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

}
