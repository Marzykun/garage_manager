import 'package:flutter/material.dart';
import 'package:garage_manager/screens/login_screen.dart';
import 'package:garage_manager/services/api_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Garage Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: LoginScreen(apiService: ApiService()),
    );
  }
}
