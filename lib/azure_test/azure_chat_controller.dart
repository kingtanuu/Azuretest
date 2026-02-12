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
  int _historyDays = 7; // 過去何日分の履歴を読み込むか（従来の方式用）
  
  // キーワードベースの検索を有効にするか
  bool _useKeywordSearch = true;

  // トピック変化検出用
  final List<ChatMessage> _currentTopicMessages = []; // 現在のトピックの会話
  String? _currentTopic; // 現在のトピック
  int _topicCounter = 0; // 今日のトピック番号カウンター
  String? _currentTopicId; // 現在のトピックID（例: topic_1）
  int _currentTopicCharCount = 0; // 現在のトピックの累積文字数
  static const int _topicCharThreshold = 3000; // キーワード中間保存の閾値

  // コンストラクタ
  AzureChatController() {
    _initializeTopicCounter();
    // キーワードベース検索を使用しない場合のみ履歴読み込み
    if (!_useKeywordSearch) {
      _loadRecentHistory();
    }
  }
  
  /// 今日のトピックカウンターを初期化
  Future<void> _initializeTopicCounter() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('ユーザーが認証されていません');
        return;
      }

      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      
      // 今日の既存トピック数を取得
      final topicsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chat')
          .doc('chat_$dateStr')
          .collection('topics')
          .get();
      
      _topicCounter = topicsSnapshot.docs.length;
      print('📊 今日のトピック数: $_topicCounter');
    } catch (e) {
      print('トピックカウンター初期化エラー: $e');
      _topicCounter = 0;
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

    // メッセージは即座にFirestoreに保存せず、トピック単位でまとめて保存

    try {
      // キーワードベースの検索を使用する場合
      if (_useKeywordSearch) {
        print('');
        print('════════════════════════════════════════════');
        print('🚀 キーワードベース検索モード');
        print('════════════════════════════════════════════');
        
        final keywords = await _extractKeywords(text);
        
        final relevantHistory = await _searchRelevantConversations(keywords);
        
        // 現在のトピックのメッセージのみを使用（新しいトピックの場合は空）
        final currentTopicHistory = _currentTopicMessages.map((msg) {
          return {
            'role': msg.role == MessageRole.user ? 'user' : 'assistant',
            'content': msg.content,
          };
        }).toList();
        
        final conversationHistory = [
          ...relevantHistory,
          ...currentTopicHistory,
          {'role': 'user', 'content': text}, // 現在のユーザーメッセージ
        ];
        
        print('💬 AIに送信する合計メッセージ数: ${conversationHistory.length}件');
        print('   - 関連する過去の会話: ${relevantHistory.length}件');
        print('   - 現在のトピック: ${currentTopicHistory.length}件');
        print('   - 今回のメッセージ: 1件');
        print('');

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
        
        // 新しいトピックの場合、トピックIDを生成
        if (_currentTopicId == null) {
          _topicCounter++;
          _currentTopicId = 'topic_$_topicCounter';
          _currentTopicCharCount = 0;
          print('🆕 新しいトピック開始: $_currentTopicId');
        }
        
        // 現在のトピックに会話を追加
        _currentTopicMessages.add(userMessage);
        _currentTopicMessages.add(assistantMessage);
        
        // 文字数を累積
        _currentTopicCharCount += userMessage.content.length + assistantMessage.content.length;
        print('📝 現在のトピック文字数: $_currentTopicCharCount文字');
        
        // トピック変化を検出
        final topicChanged = await _detectTopicChange(userMessage, assistantMessage);
        
        if (topicChanged) {
          print('');
          print('🔄 トピック変化を検出！前のトピックを保存します');
          
          // 前のトピックから今回の会話を除外して保存
          if (_currentTopicMessages.length >= 2) {
            _currentTopicMessages.removeLast(); // assistantMessage
            _currentTopicMessages.removeLast(); // userMessage
          }
          
          if (_currentTopicMessages.isNotEmpty && _currentTopicId != null) {
            // 前のトピックを保存
            await _saveTopicToFirestore();
            // キーワードを保存
            await _saveCurrentTopicKeywords();
          }
          
          // 新しいトピックとして現在の会話をセット
          _currentTopicMessages.clear();
          _currentTopicMessages.add(userMessage);
          _currentTopicMessages.add(assistantMessage);
          _currentTopic = null;
          _currentTopicId = null; // 次のメッセージで新しいIDを生成
          _currentTopicCharCount = userMessage.content.length + assistantMessage.content.length;
          
          // 新しいトピックを保存
          await _saveTopicToFirestore();
        } else {
          // トピック継続中 - トピックを保存
          await _saveTopicToFirestore();
          
          if (_currentTopicCharCount >= _topicCharThreshold) {
            // 3000文字超えたら中間保存
            print('');
            print('📏 トピックが長くなりました（$_currentTopicCharCount文字）- キーワードを中間保存します');
            await _saveCurrentTopicKeywords(isIntermediate: true);
            _currentTopicCharCount = 0; // リセット
          }
        }
      } else {
        // 従来の方式（7日分全て）
        final historyContext = _buildHistoryContext();
        print('📚 過去の履歴をコンテキストに追加: ${historyContext.length}件');
        
        final conversationHistory = [
          ...historyContext,
          ..._messages.map((msg) {
            return {
              'role': msg.role == MessageRole.user ? 'user' : 'assistant',
              'content': msg.content,
            };
          }).toList(),
        ];
        
        print('💬 AIに送信する合計メッセージ数: ${conversationHistory.length}件');

        final response = await _azureService.sendChatMessage(
          messages: conversationHistory,
          systemPrompt: _systemPrompt,
        );

        final assistantMessage = ChatMessage(
          role: MessageRole.assistant,
          content: response,
          timestamp: DateTime.now(),
        );
        _messages.add(assistantMessage);
      }
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

    // メッセージは即座にFirestoreに保存せず、トピック単位でまとめて保存

    try {
      // キーワードベースの検索を使用する場合
      if (_useKeywordSearch) {
        print('');
        print('════════════════════════════════════════════');
        print('🚀 キーワードベース検索モード（ストリーミング）');
        print('════════════════════════════════════════════');
        
        final keywords = await _extractKeywords(text);
        
        final relevantHistory = await _searchRelevantConversations(keywords);
        
        // 現在のトピックのメッセージのみを使用（新しいトピックの場合は空）
        final currentTopicHistory = _currentTopicMessages.map((msg) {
          return {
            'role': msg.role == MessageRole.user ? 'user' : 'assistant',
            'content': msg.content,
          };
        }).toList();
        
        final conversationHistory = [
          ...relevantHistory,
          ...currentTopicHistory,
          {'role': 'user', 'content': text}, // 現在のユーザーメッセージ
        ];
        
        print('💬 AIに送信する合計メッセージ数: ${conversationHistory.length}件');
        print('   - 関連する過去の会話: ${relevantHistory.length}件');
        print('   - 現在のトピック: ${currentTopicHistory.length}件');
        print('   - 今回のメッセージ: 1件');
        print('');

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
          assistantMessage.content += chunk;
          notifyListeners();
        }
        
        if (assistantMessage.content.isNotEmpty) {
          // 新しいトピックの場合、トピックIDを生成
          if (_currentTopicId == null) {
            _topicCounter++;
            _currentTopicId = 'topic_$_topicCounter';
            _currentTopicCharCount = 0;
            print('🆕 新しいトピック開始: $_currentTopicId');
          }
          
          // 現在のトピックに会話を追加
          _currentTopicMessages.add(userMessage);
          _currentTopicMessages.add(assistantMessage);
          
          // 文字数を累積
          _currentTopicCharCount += userMessage.content.length + assistantMessage.content.length;
          print('📝 現在のトピック文字数: $_currentTopicCharCount文字');
          
          // トピック変化を検出
          final topicChanged = await _detectTopicChange(userMessage, assistantMessage);
          
          if (topicChanged) {
            print('');
            print('🔄 トピック変化を検出！前のトピックを保存します');
            
            // 前のトピックから今回の会話を除外して保存
            if (_currentTopicMessages.length >= 2) {
              _currentTopicMessages.removeLast(); // assistantMessage
              _currentTopicMessages.removeLast(); // userMessage
            }
            
            if (_currentTopicMessages.isNotEmpty && _currentTopicId != null) {
              // 前のトピックを保存
              await _saveTopicToFirestore();
              // キーワードを保存
              await _saveCurrentTopicKeywords();
            }
            
            // 新しいトピックとして現在の会話をセット
            _currentTopicMessages.clear();
            _currentTopicMessages.add(userMessage);
            _currentTopicMessages.add(assistantMessage);
            _currentTopic = null;
            _currentTopicId = null; // 次のメッセージで新しいIDを生成
            _currentTopicCharCount = userMessage.content.length + assistantMessage.content.length;
            
            // 新しいトピックを保存
            await _saveTopicToFirestore();
          } else {
            // トピック継続中 - トピックを保存
            await _saveTopicToFirestore();
            
            if (_currentTopicCharCount >= _topicCharThreshold) {
              // 3000文字超えたら中間保存
              print('');
              print('📏 トピックが長くなりました（$_currentTopicCharCount文字）- キーワードを中間保存します');
              await _saveCurrentTopicKeywords(isIntermediate: true);
              _currentTopicCharCount = 0; // リセット
            }
          }
        }
      } else {
        // 従来の方式（7日分全て）
        final historyContext = _buildHistoryContext();
        print('📚 過去の履歴をコンテキストに追加: ${historyContext.length}件');
        
        final conversationHistory = [
          ...historyContext,
          ..._messages.map((msg) {
            return {
              'role': msg.role == MessageRole.user ? 'user' : 'assistant',
              'content': msg.content,
            };
          }).toList(),
        ];
        
        print('💬 AIに送信する合計メッセージ数: ${conversationHistory.length}件');

        final assistantMessage = ChatMessage(
          role: MessageRole.assistant,
          content: '',
          timestamp: DateTime.now(),
        );
        _messages.add(assistantMessage);
        notifyListeners();

        await for (var chunk in _azureService.sendChatMessageStream(
          messages: conversationHistory,
          systemPrompt: _systemPrompt,
        )) {
          assistantMessage.content += chunk;
          notifyListeners();
        }
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
    // クリア前に最後のトピックのキーワードを保存
    if (_currentTopicMessages.isNotEmpty) {
      _saveCurrentTopicKeywords();
    }
    
    _messages.clear();
    _errorMessage = null;
    
    // トピック情報もクリア
    _currentTopicMessages.clear();
    _currentTopic = null;
    _currentTopicId = null;
    _currentTopicCharCount = 0;
    
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

  /// キーワードベース検索の有効/無効を切り替え
  void setUseKeywordSearch(bool value) {
    _useKeywordSearch = value;
    notifyListeners();
  }

  /// テキストからキーワードを抽出
  Future<List<String>> _extractKeywords(String text) async {
    try {
      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔍 キーワード抽出開始');
      print('📝 入力テキスト: "$text"');
      
      final prompt = '''
以下のテキストから、検索に適した実体的なキーワードを3〜8個抽出してください。

【重要】必ず含めるべきキーワード:
1. 話題のジャンル（スポーツ、趣味、技術、料理、ビジネス、エンターテイメントなど）
2. 具体的な単語や固有名詞

【抽出ルール】
✅ 抽出すべきキーワード:
- 話題のジャンル（必須）：スポーツ、趣味、技術、料理、音楽、映画、ゲーム、ビジネス、教育、健康など
- 固有名詞（人名、地名、商品名など）
- 具体的な物や概念（野球、サッカー、ゲーム、料理など）
- 専門用語や特定の分野の言葉
- 複合語は意味のある単位で分解（例：「システムプロンプト」→「システムプロンプト, システム, プロンプト」）

❌ 避けるべき言葉:
- 動詞（話す、見る、行くなど）
- 形容詞・副詞（好き、嬉しい、とてもなど）
- 一般的すぎる言葉（こと、もの、人など）
- 意味のない2文字の分割（「シス」「テム」「プロ」「ンプ」など）

【例】
入力: 「野球選手の話したい」
正しい出力: スポーツ, 野球選手, 野球, 選手

入力: 「プロ野球の話しよう」
正しい出力: スポーツ, プロ野球, プロ, 野球
誤った出力: プロ野球, プロ, 野球, スポーツ, スポ, ーツ

入力: 「最近マラソン始めました」
正しい出力: スポーツ, 趣味, マラソン, ランニング, 運動

入力: 「システムプロンプトを変更したい」
正しい出力: 技術, システムプロンプト, システム, プロンプト, 設定
誤った出力: システムプロンプト, シス, テム, プロ, ンプ

入力: 「カレーの作り方を教えて」
正しい出力: 料理, カレー, レシピ, 調理

テキスト: $text

重要: 「キーワード:」などのプレフィックスは不要です。カンマ区切りのキーワードのみを出力してください。''';

      final response = await _azureService.sendChatMessage(
        messages: [{'role': 'user', 'content': prompt}],
        systemPrompt: 'あなたはテキスト分析の専門家です。余計な説明やプレフィックスは一切付けず、カンマ区切りのキーワードのみを出力してください。【重要】必ず話題のジャンル（スポーツ、趣味、技術、料理など）を最初に含めてください。複合語は意味のある単位で分解してください（例: 野球選手→スポーツ,野球選手,野球,選手）。意味のない2文字の分割は絶対にしないでください。',
      );

      print('🤖 AIの応答: "$response"');

      // レスポンスからキーワードを抽出（カンマ区切り）
      final step1 = response.replaceAll('\n', ',');
      print('[DEBUG] step1 改行→カンマ: "$step1"');
      
      final step2 = step1.split(',');
      print('[DEBUG] step2 split後: $step2');
      
      final keywords = step2
          .map((k) => k.trim())
          .map((k) {
            // あらゆるプレフィックスパターンを削除
            k = k.replaceAll(RegExp(r'^(キーワード|keyword|Keywords|出力|結果)[:：\s]*', caseSensitive: false), '');
            // 数字と記号のプレフィックスを削除（1. や - など）
            k = k.replaceAll(RegExp(r'^\d+[.．)\s]*'), '');
            k = k.replaceAll(RegExp(r'^[-・*]\s*'), '');
            // 句読点や記号を削除
            k = k.replaceAll(RegExp('[。、.,!?！？\\s]+\$'), '');
            // 前後のクォートを削除
            k = k.replaceAll(RegExp('^[「『"\']'), '');
            k = k.replaceAll(RegExp('[」』"\']\$'), '');
            return k.trim();
          })
          .where((k) => k.isNotEmpty && k.length > 1) // 1文字のキーワードも除外
          .toList();

      print('✅ 抽出されたキーワード: ${keywords.join(", ")} (${keywords.length}個)');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('');
      
      return keywords;
    } catch (e) {
      print('❌ キーワード抽出エラー: $e');
      return [];
    }
  }

  /// トピック変化を検出
  Future<bool> _detectTopicChange(
    ChatMessage userMessage,
    ChatMessage assistantMessage,
  ) async {
    // 最初の会話の場合は変化なし
    if (_currentTopicMessages.length <= 2) {
      return false;
    }
    
    try {
      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔍 トピック変化検出');
      
      // 過去の会話の要約を作成
      final previousConversation = _currentTopicMessages
          .take(_currentTopicMessages.length - 2) // 今回の会話を除く
          .map((m) => '${m.role == MessageRole.user ? "User" : "Assistant"}: ${m.content}')
          .join('\n');
      
      final currentConversation = '''
User: ${userMessage.content}
Assistant: ${assistantMessage.content}''';
      
      final prompt = '''
以下の2つの会話を比較して、話題の主題（メイントピック）が変わったかを判定してください。

【これまでの話題】
$previousConversation

【今回の発言】
$currentConversation

判定基準（厳密に判定してください）:
✅ YES（話題が変わった）の例:
- 野球の話 → サッカーの話
- 料理の話 → 旅行の話
- 仕事の話 → 趣味の話
- プログラミングの話 → 音楽の話
- 全く異なる主題に切り替わった場合

❌ NO（同じ話題の継続）の例:
- 野球の話 → 同じく野球の別の側面（選手、チーム、ルール等）
- 前の質問への返答や補足
- 話題の掘り下げや関連する質問
- 相槌や感想

重要: 主題（メインテーマ）が明確に異なる場合はYESと判定してください。

回答: YES または NO のみ''';

      final response = await _azureService.sendChatMessage(
        messages: [{'role': 'user', 'content': prompt}],
        systemPrompt: 'あなたは会話の主題分類の専門家です。異なる主題への切り替えを正確に検出してください。「野球→サッカー」のような明確な主題の変化は必ずYESと判定してください。',
      );
      
      print('🤖 AI判定: $response');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('');
      
      // YES が含まれていればトピック変化と判定（大文字小文字を区別しない）
      final topicChanged = response.toUpperCase().contains('YES');
      
      if (topicChanged) {
        print('✅ トピック変化: あり');
      } else {
        print('➡️ トピック変化: なし（継続）');
      }
      
      return topicChanged;
    } catch (e) {
      print('❌ トピック変化検出エラー: $e');
      return false; // エラー時は変化なしとして継続
    }
  }

  /// 現在のトピックのキーワードを保存
  Future<void> _saveCurrentTopicKeywords({bool isIntermediate = false}) async {
    if (_currentTopicMessages.isEmpty || _currentTopicId == null) return;
    
    try {
      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      if (isIntermediate) {
        print('� トピック中間 - キーワード保存開始');
      } else {
        print('🔑 トピック終了 - キーワード保存開始');
      }
      print('📊 対象会話数: ${_currentTopicMessages.length}件');
      print('🏷️  トピックID: $_currentTopicId');
      print('ℹ️  ※会話は既にトピックに保存済み、キーワードのみ保存します');
      
      // 会話全体からキーワードを抽出
      final conversationText = _currentTopicMessages
          .map((m) => m.content)
          .join('\n');
      
      final keywords = await _extractKeywords(conversationText);
      
      if (keywords.isEmpty) {
        print('⚠️ キーワードが抽出されませんでした');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('');
        return;
      }
      
      // キーワードから日付とトピックIDへの参照を保存
      await _saveKeywordReferences(keywords);
      
      print('✅ キーワード保存完了');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('');
    } catch (e) {
      print('❌ キーワード保存エラー: $e');
    }
  }
  
  /// トピックをFirestoreに保存
  Future<void> _saveTopicToFirestore() async {
    try {
      print('[DEBUG] _saveTopicToFirestore 開始');
      final user = _auth.currentUser;
      print('[DEBUG] user: ${user?.uid}');
      print('[DEBUG] _currentTopicId: $_currentTopicId');
      print('[DEBUG] _currentTopicMessages.length: ${_currentTopicMessages.length}');
      
      if (user == null || _currentTopicId == null || _currentTopicMessages.isEmpty) {
        print('[DEBUG] 早期リターン: user=$user, topicId=$_currentTopicId, messagesCount=${_currentTopicMessages.length}');
        return;
      }
      
      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      print('[DEBUG] dateStr: $dateStr');
      
      // users/{uid}/chat/{chat_YYYYMMDD}/topics/{topic_id}
      final topicRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chat')
          .doc('chat_$dateStr')
          .collection('topics')
          .doc(_currentTopicId!);
      
      final messagesData = _currentTopicMessages
          .where((msg) => msg.content.isNotEmpty) // 空のメッセージを除外
          .map((msg) {
            print('[DEBUG] メッセージ変換: role=${msg.role}, contentLength=${msg.content.length}');
            return {
              'role': msg.role == MessageRole.user ? 'user' : 'assistant',
              'content': msg.content,
              'timestamp': Timestamp.fromDate(msg.timestamp),
            };
          }).toList();
      
      print('[DEBUG] messagesData.length: ${messagesData.length}');
      
      // メッセージが空の場合は保存しない
      if (messagesData.isEmpty) {
        print('⚠️ 保存するメッセージがありません');
        return;
      }
      
      print('[DEBUG] Firestore保存開始');
      await topicRef.set({
        'messages': messagesData,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('[DEBUG] Firestore保存完了');
      print('✅ トピック保存完了: $_currentTopicId');
    } catch (e, stackTrace) {
      print('❌ トピック保存エラー: $e');
      print('スタックトレース: $stackTrace');
    }
  }

  /// キーワードから日付・トピックへの参照を保存
  Future<void> _saveKeywordReferences(List<String> keywords) async {
    try {
      final user = _auth.currentUser;
      if (user == null || keywords.isEmpty || _currentTopicId == null) return;

      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('💾 キーワード参照保存開始');
      print('📌 保存するキーワード: ${keywords.join(", ")}');

      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      print('📅 保存日付: $dateStr');
      print('🏷️  トピックID: $_currentTopicId');

      for (final keyword in keywords) {
        print('');
        print('  ▶ キーワード: "$keyword"');
        
        final keywordRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('keywords')
            .doc(keyword);

        final reference = {
          'date': dateStr,
          'topicId': _currentTopicId!,
          'timestamp': Timestamp.fromDate(DateTime.now()),
        };

        final docSnapshot = await keywordRef.get();
        
        if (docSnapshot.exists) {
          print('    ℹ️  既存のキーワード - 参照を追加');
          await keywordRef.update({
            'references': FieldValue.arrayUnion([reference]),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          print('    ✅ 参照追加完了');
        } else {
          print('    🆕 新しいキーワード - 作成します');
          await keywordRef.set({
            'keyword': keyword,
            'references': [reference],
            'createdAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          print('    ✅ 作成完了');
        }
      }

      print('');
      print('✅ 全キーワード参照の保存完了');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('');
    } catch (e) {
      print('❌ キーワード参照保存エラー: $e');
    }
  }

  /// キーワードに基づいて関連する会話を検索（参照ベース）
  Future<List<Map<String, String>>> _searchRelevantConversations(
    List<String> keywords,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null || keywords.isEmpty) {
        return [];
      }

      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔎 関連会話の検索開始（完全一致 + 部分一致）');
      print('🔑 検索キーワード: ${keywords.join(", ")}');

      final relevantMessages = <Map<String, String>>[];
      final addedTopics = <String, int>{}; // トピックとその優先度（1=完全一致, 2=部分一致）

      // フェーズ1: 完全一致検索
      print('');
      print('📍 フェーズ1: 完全一致検索');
      for (final keyword in keywords) {
        print('  ▶ "$keyword" (完全一致)');
        
        final keywordRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('keywords')
            .doc(keyword);

        final docSnapshot = await keywordRef.get();
        if (!docSnapshot.exists) {
          print('    ⚠️  見つかりませんでした');
          continue;
        }

        final data = docSnapshot.data();
        final references = data?['references'] as List<dynamic>? ?? [];
        print('    ✅ ${references.length}件の参照を発見');

        // 最新の参照から最大3件まで
        final recentReferences = references.reversed.take(3);
        
        for (var ref in recentReferences) {
          final date = ref['date'] as String;
          final topicId = ref['topicId'] as String;
          final topicKey = '${date}_$topicId';
          
          if (!addedTopics.containsKey(topicKey)) {
            addedTopics[topicKey] = 1; // 完全一致の優先度
            print('    📌 追加: $topicKey (完全一致)');
          }
        }
      }

      // フェーズ2: 部分一致検索（完全一致で見つからなかったキーワードのみ）
      print('');
      print('📍 フェーズ2: 部分一致検索');
      
      // すべてのキーワードドキュメントを取得
      final allKeywordsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('keywords')
          .get();
      
      print('  📚 保存済みキーワード総数: ${allKeywordsSnapshot.docs.length}個');

      for (final keyword in keywords) {
        print('  ▶ "$keyword" の部分一致を検索中...');
        
        int partialMatchCount = 0;
        for (var keywordDoc in allKeywordsSnapshot.docs) {
          final savedKeyword = keywordDoc.id;
          
          // 部分一致チェック（完全一致は除外）
          if (savedKeyword != keyword && savedKeyword.contains(keyword)) {
            print('    🔍 部分一致発見: "$savedKeyword"');
            
            final data = keywordDoc.data();
            final references = data['references'] as List<dynamic>? ?? [];
            
            // 最新の参照から最大2件まで（部分一致は控えめに）
            final recentReferences = references.reversed.take(2);
            
            for (var ref in recentReferences) {
              final date = ref['date'] as String;
              final topicId = ref['topicId'] as String;
              final topicKey = '${date}_$topicId';
              
              if (!addedTopics.containsKey(topicKey)) {
                addedTopics[topicKey] = 2; // 部分一致の優先度
                print('      📌 追加: $topicKey (部分一致)');
                partialMatchCount++;
              }
            }
          }
        }
        
        if (partialMatchCount == 0) {
          print('    ⚠️  部分一致も見つかりませんでした');
        } else {
          print('    ✅ ${partialMatchCount}件のトピックを追加');
        }
      }

      // トピックを優先度順にソート（完全一致を優先）
      final sortedTopics = addedTopics.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      print('');
      print('📊 検索結果サマリー:');
      print('  - 完全一致トピック: ${addedTopics.values.where((v) => v == 1).length}個');
      print('  - 部分一致トピック: ${addedTopics.values.where((v) => v == 2).length}個');
      print('  - 合計: ${sortedTopics.length}個');

      // トピックの会話を取得
      print('');
      print('📖 トピックの会話を取得中...');
      for (var entry in sortedTopics) {
        final topicKey = entry.key;
        final priority = entry.value;
        final parts = topicKey.split('_');
        final date = parts[0];
        final topicId = parts[1];
        
        final matchType = priority == 1 ? '完全一致' : '部分一致';
        print('  ▶ $topicKey ($matchType)');

        final topicRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('chat')
            .doc('chat_$date')
            .collection('topics')
            .doc(topicId);
        
        final topicSnapshot = await topicRef.get();
        if (!topicSnapshot.exists) {
          print('    ⚠️  トピックが見つかりません');
          continue;
        }
        
        final topicData = topicSnapshot.data();
        final messages = topicData?['messages'] as List<dynamic>? ?? [];
        
        print('    ✅ ${messages.length}メッセージを追加');
        
        for (var msg in messages) {
          final role = msg['role'] as String;
          final content = msg['content'] as String;
          
          relevantMessages.add({
            'role': role,
            'content': content,
          });
        }
      }

      print('');
      print('✅ 検索完了');
      print('📚 取得した関連メッセージ総数: ${relevantMessages.length}件');
      print('💬 トピック数: ${sortedTopics.length}個');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('');
      
      return relevantMessages;
    } catch (e) {
      print('❌ 会話検索エラー: $e');
      return [];
    }
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
