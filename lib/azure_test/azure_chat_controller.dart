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

  // 過去の会話履歴（コンテキスト用）
  final List<ChatMessage> _historyMessages = [];
  int _historyDays = 7; // 過去何日分の履歴を読み込むか

  // コンストラクタ - 初期化時に今日のチャットドキュメントを作成と履歴読み込み
  AzureChatController() {
    _initializeTodayChat();
    _loadRecentHistory();
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

  /// 過去の会話履歴を読み込む
  Future<void> _loadRecentHistory() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('ユーザーが認証されていません');
        return;
      }

      _historyMessages.clear();

      // 今日を含む過去N日分の日付を生成
      final now = DateTime.now();
      final dates = List.generate(_historyDays + 1, (i) {
        final date = now.subtract(Duration(days: i));
        return DateFormat('yyyyMMdd').format(date);
      });

      // 各日付のチャット履歴を取得
      for (final dateStr in dates) {
        final docId = 'allchat_$dateStr';
        final chatRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('chat')
            .doc(docId);

        final docSnapshot = await chatRef.get();
        if (docSnapshot.exists) {
          final data = docSnapshot.data();
          final messagesList = data?['messages'] as List<dynamic>? ?? [];

          for (var msgData in messagesList) {
            final role = msgData['role'] == 'user' 
                ? MessageRole.user 
                : MessageRole.assistant;
            final content = msgData['content'] as String;
            final timestamp = (msgData['timestamp'] as Timestamp).toDate();

            _historyMessages.add(ChatMessage(
              role: role,
              content: content,
              timestamp: timestamp,
            ));
          }
        }
      }

      print('会話履歴読み込み完了: ${_historyMessages.length}件（今日含む過去${_historyDays + 1}日分）');
    } catch (e) {
      print('会話履歴読み込みエラー: $e');
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
      // 会話履歴を構築（過去の履歴 + 現在の会話）
      final historyContext = _buildHistoryContext();
      print('📚 過去の履歴をコンテキストに追加: ${historyContext.length}件');
      
      final conversationHistory = [
        // 過去の履歴（要約版またはサンプリング）
        ...historyContext,
        // 現在の会話
        ..._messages.map((msg) {
          return {
            'role': msg.role == MessageRole.user ? 'user' : 'assistant',
            'content': msg.content,
          };
        }).toList(),
      ];
      
      print('💬 AIに送信する合計メッセージ数: ${conversationHistory.length}件');

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
      // 会話履歴を構築（過去の履歴 + 現在の会話）
      final historyContext = _buildHistoryContext();
      print('📚 過去の履歴をコンテキストに追加: ${historyContext.length}件');
      
      final conversationHistory = [
        // 過去の履歴（要約版またはサンプリング）
        ...historyContext,
        // 現在の会話
        ..._messages.map((msg) {
          return {
            'role': msg.role == MessageRole.user ? 'user' : 'assistant',
            'content': msg.content,
          };
        }).toList(),
      ];
      
      print('💬 AIに送信する合計メッセージ数: ${conversationHistory.length}件');

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

  /// 過去の履歴をコンテキストとして構築
  /// トークン制限を考慮して、適切な範囲をサンプリング
  List<Map<String, String>> _buildHistoryContext() {
    if (_historyMessages.isEmpty) {
      print('⚠️ 過去の履歴が空です');
      return [];
    }

    print('📖 過去の履歴総数: ${_historyMessages.length}件');

    // トークン数の概算（1トークン ≈ 4文字として計算）
    const maxHistoryTokens = 2000; // 履歴用に確保するトークン数
    int currentTokens = 0;
    final contextMessages = <Map<String, String>>[];

    // 新しいものから順に追加（最近の会話を優先）
    for (int i = _historyMessages.length - 1; i >= 0; i--) {
      final msg = _historyMessages[i];
      final estimatedTokens = (msg.content.length / 4).ceil();
      
      if (currentTokens + estimatedTokens > maxHistoryTokens) {
        print('⚠️ トークン制限に達しました。${contextMessages.length}件の履歴を使用');
        break;
      }

      contextMessages.insert(0, {
        'role': msg.role == MessageRole.user ? 'user' : 'assistant',
        'content': msg.content,
      });
      currentTokens += estimatedTokens;
    }

    print('✅ コンテキストに追加する履歴: ${contextMessages.length}件（約${currentTokens}トークン）');
    return contextMessages;
  }

  /// 履歴読み込み日数を設定
  void setHistoryDays(int days) {
    _historyDays = days;
    _loadRecentHistory();
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

  /// テスト用の過去の会話データを追加
  Future<void> addTestHistoryData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('ユーザーが認証されていません');
        return;
      }

      print('📝 テストデータを追加中...');

      // 3日前のマラソンの会話
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      final date3 = DateFormat('yyyyMMdd').format(threeDaysAgo);
      
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chat')
          .doc('allchat_$date3')
          .set({
        'date': date3,
        'messages': [
          {
            'role': 'user',
            'content': '最近マラソンを始めました！',
            'timestamp': Timestamp.fromDate(threeDaysAgo),
          },
          {
            'role': 'assistant',
            'content': 'マラソンを始めたんですね！素晴らしいです。健康的な趣味ですね。どれくらいの距離を走っていますか？',
            'timestamp': Timestamp.fromDate(threeDaysAgo.add(const Duration(seconds: 5))),
          },
          {
            'role': 'user',
            'content': '週に3回、5キロくらい走っています',
            'timestamp': Timestamp.fromDate(threeDaysAgo.add(const Duration(minutes: 1))),
          },
          {
            'role': 'assistant',
            'content': '週3回で5キロとは良いペースですね！継続が大切です。フルマラソンに挑戦する予定はありますか？',
            'timestamp': Timestamp.fromDate(threeDaysAgo.add(const Duration(minutes: 1, seconds: 5))),
          },
        ],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ 3日前のデータを追加: allchat_$date3');

      // 5日前の野球の会話
      final fiveDaysAgo = DateTime.now().subtract(const Duration(days: 5));
      final date5 = DateFormat('yyyyMMdd').format(fiveDaysAgo);
      
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chat')
          .doc('allchat_$date5')
          .set({
        'date': date5,
        'messages': [
          {
            'role': 'user',
            'content': '野球観戦が好きで、よく球場に行きます',
            'timestamp': Timestamp.fromDate(fiveDaysAgo),
          },
          {
            'role': 'assistant',
            'content': '野球観戦が趣味なんですね！どこのチームのファンですか？球場で見る野球は臨場感がありますよね。',
            'timestamp': Timestamp.fromDate(fiveDaysAgo.add(const Duration(seconds: 5))),
          },
          {
            'role': 'user',
            'content': 'ジャイアンツファンです！',
            'timestamp': Timestamp.fromDate(fiveDaysAgo.add(const Duration(minutes: 1))),
          },
          {
            'role': 'assistant',
            'content': '読売ジャイアンツのファンなんですね！伝統のあるチームです。東京ドームにはよく行かれますか？',
            'timestamp': Timestamp.fromDate(fiveDaysAgo.add(const Duration(minutes: 1, seconds: 5))),
          },
        ],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ 5日前のデータを追加: allchat_$date5');
      print('🎉 テストデータの追加が完了しました');
      
      // データ追加後、履歴を再読み込み
      await _loadRecentHistory();
      
    } catch (e) {
      print('❌ テストデータ追加エラー: $e');
    }
  }
}
