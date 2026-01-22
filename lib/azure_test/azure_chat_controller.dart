// lib/azure_test/azure_chat_controller.dart
/// Azure OpenAI を使用したチャットコントローラー

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'azure_openai_service.dart';
import 'models.dart';

class AzureChatController extends ChangeNotifier {
  final AzureOpenAIService _azureService = AzureOpenAIService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 会話履歴
  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  
  // ローディング状態
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  // エラーメッセージ
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  
  // システムプロンプト（キャラクター設定など）
  String _systemPrompt = 'You are a helpful assistant.';
  String get systemPrompt => _systemPrompt;
  
  set systemPrompt(String value) {
    _systemPrompt = value;
    notifyListeners();
  }

  // コンストラクタ - 初期化時に今日のチャットドキュメントを作成
  AzureChatController() {
    _initializeTodayChat();
  }
  
  /// 今日のチャットドキュメントを初期化
  Future<void> _initializeTodayChat() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('ユーザーが認証されていません');
        return;
      }

      // 今日の日付を取得（YYYYMMDD形式）
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final docId = 'allchat_$dateStr';

      // users/{uid}/chat/{allchat_YYYYMMDD} のパスをチェック
      final chatRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chat')
          .doc(docId);

      final docSnapshot = await chatRef.get();
      if (!docSnapshot.exists) {
        // ドキュメントが存在しない場合は作成
        await chatRef.set({
          'date': dateStr,
          'createdAt': FieldValue.serverTimestamp(),
          'messages': [],
        });
        print('今日のチャットドキュメント作成: $docId');
      } else {
        print('今日のチャットドキュメント既存: $docId');
      }
    } catch (e) {
      print('チャットドキュメント初期化エラー: $e');
    }
  }

  /// メッセージを送信（通常版）
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    // ユーザーメッセージを追加
    final userMessage = ChatMessage(
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    );
    _messages.add(userMessage);
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    // Firestoreに保存
    await _saveChatMessage(userMessage);

    try {
      // 会話履歴を構築
      final conversationHistory = _messages.map((msg) {
        return {
          'role': msg.role == MessageRole.user ? 'user' : 'assistant',
          'content': msg.content,
        };
      }).toList();

      // Azure OpenAI にリクエスト
      final response = await _azureService.sendChatMessage(
        messages: conversationHistory,
        systemPrompt: _systemPrompt,
      );

      // アシスタントの応答を追加
      final assistantMessage = ChatMessage(
        role: MessageRole.assistant,
        content: response,
        timestamp: DateTime.now(),
      );
      _messages.add(assistantMessage);
      
      // Firestoreに保存
      await _saveChatMessage(assistantMessage);
    } catch (e) {
      _errorMessage = 'エラーが発生しました: $e';
      print('送信エラー: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// メッセージを送信（ストリーミング版）
  /// 
  /// リアルタイムで応答を受け取り、表示を更新します
  Future<void> sendMessageStream(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    // ユーザーメッセージを追加
    final userMessage = ChatMessage(
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    );
    _messages.add(userMessage);
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();

    // Firestoreに保存
    await _saveChatMessage(userMessage);

    try {
      // 会話履歴を構築
      final conversationHistory = _messages.map((msg) {
        return {
          'role': msg.role == MessageRole.user ? 'user' : 'assistant',
          'content': msg.content,
        };
      }).toList();

      // アシスタントメッセージの準備（空の状態で追加）
      final assistantMessage = ChatMessage(
        role: MessageRole.assistant,
        content: '',
        timestamp: DateTime.now(),
      );
      _messages.add(assistantMessage);
      notifyListeners();

      // ストリーミングでレスポンスを受信
      await for (var chunk in _azureService.sendChatMessageStream(
        messages: conversationHistory,
        systemPrompt: _systemPrompt,
      )) {
        // チャンクを追加して更新
        assistantMessage.content += chunk;
        notifyListeners();
      }
      
      // ストリーミング完了後にFirestoreに保存
      if (assistantMessage.content.isNotEmpty) {
        await _saveChatMessage(assistantMessage);
      }
    } catch (e) {
      _errorMessage = 'エラーが発生しました: $e';
      print('ストリーミング送信エラー: $e');
      
      // エラーが発生した場合、最後のアシスタントメッセージを削除
      if (_messages.isNotEmpty && 
          _messages.last.role == MessageRole.assistant &&
          _messages.last.content.isEmpty) {
        _messages.removeLast();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 会話履歴をクリア
  void clearMessages() {
    _messages.clear();
    _errorMessage = null;
    notifyListeners();
  }

  /// エラーメッセージをクリア
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// チャットメッセージをFirestoreに保存
  Future<void> _saveChatMessage(ChatMessage message) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('ユーザーが認証されていません');
        return;
      }

      // 今日の日付を取得（YYYYMMDD形式）
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final docId = 'allchat_$dateStr';

      // users/{uid}/chat/{allchat_YYYYMMDD} のパスに保存
      final chatRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chat')
          .doc(docId);

      // ドキュメントが存在しない場合は作成
      final docSnapshot = await chatRef.get();
      if (!docSnapshot.exists) {
        await chatRef.set({
          'date': dateStr,
          'createdAt': FieldValue.serverTimestamp(),
          'messages': [],
        });
      }

      // メッセージを配列に追加
      await chatRef.update({
        'messages': FieldValue.arrayUnion([
          {
            'role': message.role == MessageRole.user ? 'user' : 'assistant',
            'content': message.content,
            'timestamp': Timestamp.fromDate(message.timestamp),
          }
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('チャットメッセージ保存成功: $docId');
    } catch (e) {
      print('チャットメッセージ保存エラー: $e');
    }
  }

  /// 過去の会話を読み込む
  Future<void> loadChatHistory(String date) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('ユーザーが認証されていません');
        return;
      }

      final docId = 'allchat_$date';
      final chatRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chat')
          .doc(docId);

      final docSnapshot = await chatRef.get();
      if (!docSnapshot.exists) {
        print('指定された日付の会話履歴が見つかりません: $date');
        return;
      }

      final data = docSnapshot.data();
      final messagesList = data?['messages'] as List<dynamic>? ?? [];

      _messages.clear();
      for (var msgData in messagesList) {
        final role = msgData['role'] == 'user' 
            ? MessageRole.user 
            : MessageRole.assistant;
        final content = msgData['content'] as String;
        final timestamp = (msgData['timestamp'] as Timestamp).toDate();

        _messages.add(ChatMessage(
          role: role,
          content: content,
          timestamp: timestamp,
        ));
      }

      notifyListeners();
      print('会話履歴読み込み成功: $docId (${_messages.length}件)');
    } catch (e) {
      print('会話履歴読み込みエラー: $e');
      _errorMessage = '会話履歴の読み込みに失敗しました';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _messages.clear();
    super.dispose();
  }
}
