import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../mutimon_chat/v1/firebase_options.dart';
import '../mutimon_chat/v1/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SimpleLoginScreen(),
  ));
}
