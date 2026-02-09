// lib/mutimon_chat/v1/main.dart
/// Mutimon Chat Application エントリーポイント
/// 
/// 実行方法:
/// flutter run -t lib/mutimon_chat/v1/main.dart -d chrome --dart-define=AZURE_OPENAI_API_KEY=your_api_key

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'auth/login_screen.dart';
import 'chat/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebaseの初期化
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const AzureTestApp());
}

class AzureTestApp extends StatelessWidget {
  const AzureTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Azure OpenAI Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // ログイン状態をチェック
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          
          if (snapshot.hasData) {
            // ログイン済み → チャット画面へ
            return const ChatScreen();
          } else {
            // 未ログイン → ログイン画面へ
            return const SimpleLoginScreen();
          }
        },
      ),
    );
  }
}
