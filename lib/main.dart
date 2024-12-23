// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'screens/home_screen.dart';
import 'cubits/connection_cubit.dart';
import 'services/logger.dart';

void main() {
  setupLogging();
  runApp(FeralFileApp());
}

class FeralFileApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Feral File',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: BlocProvider(
        create: (context) => ConnectionCubit()..startListening(),
        child: HomeScreen(),
      ),
    );
  }
}
