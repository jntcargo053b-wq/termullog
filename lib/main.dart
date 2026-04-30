import 'package:flutter/material.dart';

void main() {
  runApp(const TermulLogApp());
}

class TermulLogApp extends StatelessWidget {
  const TermulLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TermulLog',
      theme: ThemeData(primarySwatch: Colors.blue),
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
  final nameController = TextEditingController();

  void login() {
    if (nameController.text.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(name: nameController.text),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TermulLog Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nama Kurir'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: login, child: const Text('LOGIN')),
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final String name;
  const DashboardScreen({super.key, required this.name});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int total = 0;
  double distance = 0;

  void addDelivery() {
    setState(() {
      total++;
      distance += 1.5; // dummy jarak sementara
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TermulLog Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text("Kurir: ${widget.name}"),
            const SizedBox(height: 10),
            Text("Total Kiriman: $total"),
            Text("Total Jarak: ${distance.toStringAsFixed(2)} KM"),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: addDelivery,
              child: const Text("+ TAMBAH KIRIM"),
            ),
          ],
        ),
      ),
    );
  }
}
