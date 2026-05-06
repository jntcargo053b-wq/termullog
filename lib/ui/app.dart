import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My App',
      home: const Scaffold(
        body: Center(
          child: Text('App Running'),
        ),
      ),
    );
  }
}
