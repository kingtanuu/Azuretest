// lib/mutimon_chat/v1/auth/auth_controller.dart
/// 認証コントローラー

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 現在のユーザーを取得
  User? get currentUser => _auth.currentUser;

  /// 認証状態の変更を監視
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// メールアドレスとパスワードでログインまたは新規登録
  /// 
  /// 既存のアカウントがあればログイン、なければ新規作成
  Future<bool> signIn({
    required BuildContext context,
    required String email,
    required String password,
  }) async {
    try {
      // まずログインを試みる
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      
      // Firestoreにユーザードキュメントを作成（存在しない場合）
      await _initializeUserDocument();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ログインしました'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } on FirebaseAuthException catch (e) {
      // ユーザーが存在しない場合は新規作成
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        return await _createAccount(
          context: context,
          email: email,
          password: password,
        );
      }
      
      // その他のエラーはメッセージを表示
      String message = 'ログインに失敗しました';
      
      switch (e.code) {
        case 'wrong-password':
          message = 'パスワードが間違っています';
          break;
        case 'invalid-email':
          message = '有効なメールアドレスを入力してください';
          break;
        case 'user-disabled':
          message = 'このアカウントは無効化されています';
          break;
        case 'network-request-failed':
          message = 'ネットワークエラーが発生しました';
          break;
        case 'too-many-requests':
          message = 'リクエストが多すぎます。しばらく待ってから再試行してください';
          break;
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  /// 新規アカウントを作成
  Future<bool> _createAccount({
    required BuildContext context,
    required String email,
    required String password,
  }) async {
    try {
      // パスワードの長さをチェック
      if (password.length < 6) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('パスワードは6文字以上で設定してください'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }

      // 新規アカウント作成
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      
      // Firestoreにユーザードキュメントを作成
      await _initializeUserDocument();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('アカウントを作成してログインしました'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return true;
    } on FirebaseAuthException catch (e) {
      String message = 'アカウント作成に失敗しました';
      
      switch (e.code) {
        case 'email-already-in-use':
          message = 'このメールアドレスは既に使用されています';
          break;
        case 'invalid-email':
          message = '有効なメールアドレスを入力してください';
          break;
        case 'weak-password':
          message = 'パスワードが弱すぎます。より複雑なパスワードを設定してください';
          break;
        case 'operation-not-allowed':
          message = 'メール/パスワード認証が有効になっていません';
          break;
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  /// Firestoreにユーザードキュメントを初期化
  Future<void> _initializeUserDocument() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final userRef = _firestore.collection('users').doc(user.uid);
      final docSnapshot = await userRef.get();

      if (!docSnapshot.exists) {
        // ユーザードキュメントが存在しない場合は作成
        await userRef.set({
          'email': user.email,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('✅ ユーザードキュメント作成: ${user.uid}');
      } else {
        print('ℹ️ ユーザードキュメント既存: ${user.uid}');
      }
    } catch (e) {
      print('❌ ユーザードキュメント初期化エラー: $e');
    }
  }

  /// ログアウト
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
