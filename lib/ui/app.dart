// lib/ui/app.dart
import 'package:flutter/material.dart';
import '../screens/home_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TermulLog',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070B16),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1E90FF),
          secondary: Color(0xFFE63946),
          surface: Color(0xFF0D1325),
          background: Color(0xFF070B16),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF070B16),
          elevation: 0,
          titleTextStyle: TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          iconTheme: IconThemeData(color: Colors.white70),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFE63946),
          foregroundColor: Colors.white,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1A2540),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
