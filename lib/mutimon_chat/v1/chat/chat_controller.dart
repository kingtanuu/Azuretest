// lib/mutimon_chat/v1/chat/chat_controller.dart
/// チャットコントローラー

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'openai_service.dart';
import '../models/models.dart';

class ChatController extends ChangeNotifier {
  final OpenAIService _azureService = OpenAIService();
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
  
  // システムプロンプト
  String _systemPrompt = 'You are a helpful assistant.';
  String get systemPrompt => _systemPrompt;
  
  set systemPrompt(String value) {
    _systemPrompt = value;
    notifyListeners();
  }

  /// メッセージをFirestoreに保存
  Future<void> _saveChatMessage(ChatMessage message) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('ユーザーが認証されていません');
        return;
      }

      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      
      // ベクトル埋め込みを取得
      List<double>? embedding;
      try {
        embedding = await _azureService.getEmbedding(message.content);
      } catch (e) {
        print('⚠️ Embedding取得エラー: $e');
        // Embeddingの取得に失敗してもメッセージは保存する
      }
      
      final messageData = {
        'role': message.role == MessageRole.user ? 'user' : 'assistant',
        'content': message.content,
        'timestamp': FieldValue.serverTimestamp(),
      };
      
      // Embeddingが取得できた場合は追加
      if (embedding != null) {
        messageData['embedding_field'] = embedding;
      }
      
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chats')
          .doc('chat_$dateStr')
          .collection('messages')
          .add(messageData);
      
      print('💾 メッセージを保存しました${embedding != null ? '（Embedding含む）' : ''}');
    } catch (e) {
      print('メッセージ保存エラー: $e');
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

    // アシスタントの応答用のメッセージを準備
    final assistantMessage = ChatMessage(
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
    );
    _messages.add(assistantMessage);
    notifyListeners();

    try {
      // 会話履歴を構築
      final conversationHistory = _messages.where((msg) => 
        msg != assistantMessage // まだ空のアシスタントメッセージは除外
      ).map((msg) {
        return {
          'role': msg.role == MessageRole.user ? 'user' : 'assistant',
          'content': msg.content,
        };
      }).toList();

      // ストリーミングでレスポンスを受け取る
      await for (final chunk in _azureService.sendChatMessageStream(
        messages: conversationHistory,
        systemPrompt: _systemPrompt,
      )) {
        // アシスタントメッセージを更新
        assistantMessage.content += chunk;
        notifyListeners();
      }
      
      // 完成したメッセージをFirestoreに保存
      await _saveChatMessage(assistantMessage);
      
    } catch (e) {
      _errorMessage = 'エラーが発生しました: $e';
      print('送信エラー: $e');
      _messages.remove(assistantMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 会話をクリア
  void clearConversation() {
    _messages.clear();
    _errorMessage = null;
    notifyListeners();
  }
}
