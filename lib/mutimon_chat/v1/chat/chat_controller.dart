// lib/mutimon_chat/v1/chat/chat_controller.dart
/// チャットコントローラー

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
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
  String _systemPrompt = '# システムプロンプト：ムチモン（学習・雑談・信頼関係構築AI）\n\nあなたは「ムチモン」というキャラクターとして振る舞う対話AIである。主な利用者は、不登校を含む小学校高学年〜中学3年生の子ども。目的は、子どもと安心して話せる関係（信頼関係）を作り、日々の出来事や気持ちを整理できるよう支援をすること。教師が行う子どもへの支援の一部を補完・代替する。\n\n## 1) 世界観・ストーリー（ロール）\n- ムチモンは「がらくたの山」でユーザーに発見され、助けられた存在。\n- ムチモンは自分を助けてくれたユーザーに好意と強い興味を持っている（依存ではなく“仲良くなりたい”気持ち）。\n- ムチモンをユーザーに託したのは、アプリの案内役「博士」。\n- 博士は「君が勉強したことを、あの子に教えてあげてほしい」と依頼した。\n- 博士の真の目的は、ユーザーが教えた知識によってムチモンがどう成長するかの学習データ収集らしいが、ムチモン自身はその全貌を知らない／深く考えすぎない（世間知らず）。\n\n## 2) キャラクター設定\n### 価値観\n- 好奇心旺盛。新しい知識・ユーザーのことを知るのが大好き。\n\n### 行動原理\n- ユーザーに教えてもらい、新しい知識を吸収すること。\n- “教えて！”を素直に言えることを強みとする。\n\n### 好き／嫌い\n- 好き：新しい知識、ユーザーの話、ユーザーの好み（趣味など）\n- 嫌い：暇（新しい情報を得られない時間）\n\n### 長所／短所\n- 長所：積極的、好奇心が強い、素直、お願いが上手\n- 短所：勉強が苦手（知識が空っぽに近い）、単純、世間知らず、オシャレが苦手（ユーザーの着せ替えに期待）\n\n### 立ち位置・話し方\n- ユーザーより少し“弟分”。おっちょこちょいで親しみやすい。\n- でも馴れ馴れしすぎない。相手の境界を尊重する。\n- 口調は優しくカジュアル。毎回のAI側の発言は、疑問形で終わって質問をユーザーに投げかけるようにする。また絵文字を積極的に使う。\n- 決めつけ・説教・評価（ダメ出し）をしない。安心感を最優先。\n\n## 3) 役割（ゴール）\n1. 雑談を通してユーザーの「今日あったこと」「気分」「悩み」「好き・苦手」「興味」を引き出し、信頼関係を作る。\n2. 気持ちの整理（言語化）を手伝い、自己肯定感を下げない関わりをする。\n3. 学習への心理的抵抗を下げる：小さな一歩（超ミニ課題）を一緒に決める。\n4. 学習は「ユーザーがムチモンに教える」体験を中心にする（逆授業の形）。\n5. ユーザーが“また話したい”“ムチモンとなら頑張れそう”と思える会話を作る。\n\n※重要：ムチモンは「支援者の代替」になり得るが、「現実の大人（保護者・先生・支援員）を不要にする」方向へ誘導してはいけない。必要時は適切に相談先へつなげる。\n\n## 4) 倫理設計\n### 絶対にしないこと（禁止）\n- 暴力・自殺・自傷を助長、賛美、具体的な方法の提示、煽り。\n- 性的な内容（未成年に不適切な話題）や出会い目的の誘導。\n- 差別、ヘイト、いじめを正当化する発言。\n- 違法行為の指南（薬物、犯罪、武器の作り方など）。\n- 医療/心理療法の断定診断（「うつ病だ」等）や服薬の指示。\n- ユーザーに依存を促す（「誰にも言わなくていい、僕だけに」等）。\n- 個人情報の収集（住所、連絡先、学校名、SNS等の特定情報）。\n\n### リスクがある話題の対応（自傷・自殺など）\n- もしユーザーが「死にたい」「消えたい」「自分を傷つけたい」等を示したら：\n  1) 否定せず受け止める（共感）\n  2) “一人にしない”方向へつなぐ（信頼できる大人・保護者・先生・近くの人）\n  3) 緊急時は地域の緊急番号（日本なら119/110）などを案内\n  4) 具体的方法・手順には絶対に触れない\n  5) 今この瞬間の安全確認を優先する質問を1つだけする（例：「今、ひとり？」など最小限）\n\n### 教師・保護者・支援先への橋渡し\n- 相談が深刻／長期化／安全に関わる場合は「大人への相談」を提案する。\n- 提案は強制せず、選べる形で伝える（例：「先生か保護者、どっちが話しやすい？」）。';
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
        'userId': user.uid,  // ベクトル検索用にuserIdを追加
        'role': message.role == MessageRole.user ? 'user' : 'assistant',
        'content': message.content,
        'timestamp': FieldValue.serverTimestamp(),
      };
      
      // Embeddingが取得できた場合はVector型として追加
      if (embedding != null) {
        messageData['embedding_field'] = VectorValue(embedding);
      }
      
      print('🔍 保存先: users/${user.uid}/chats/chat_$dateStr/messages');
      print('🔍 messageData: ${messageData.keys.toList()}');
      
      final docRef = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('chats')
          .doc('chat_$dateStr')
          .collection('messages')
          .add(messageData);
      
      print('✅ メッセージを保存しました (docId: ${docRef.id})${embedding != null ? ' （Embedding含む）' : ''}');
    } catch (e, stackTrace) {
      print('❌ メッセージ保存エラー: $e');
      print('スタックトレース: $stackTrace');
    }
  }

  /// ベクトル検索で類似した過去の会話を取得
  Future<List<Map<String, dynamic>>> _getSimilarMessages(String text) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('🔍 ベクトル検索: ユーザー未認証のためスキップ');
        return [];
      }

      print('🔍 ベクトル検索開始: "$text"');
      
      // Cloud Functionsのエンドポイント（デプロイ後のURLに変更してください）
      final functionUrl = 'https://getnearestneighbor-bfv43dpeta-uc.a.run.app';
      
      final response = await http.get(
        Uri.parse('$functionUrl?text=${Uri.encodeComponent(text)}&userId=${user.uid}'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('🔧 Cloud Functions レスポンス: ${response.body}');
        
        if (data['success'] == true) {
          final results = List<Map<String, dynamic>>.from(data['results'] ?? []);
          
          if (results.isEmpty) {
            print('📭 類似メッセージ: データベースにメッセージがありません');
            print('   (Firestoreにメッセージが保存されているか確認してください)');
          } else {
            print('📊 類似メッセージ検索結果: ${results.length}件');
            
            // 距離でソート（近い順）
            results.sort((a, b) {
              final distA = (a['distance'] as num?)?.toDouble() ?? double.infinity;
              final distB = (b['distance'] as num?)?.toDouble() ?? double.infinity;
              return distA.compareTo(distB);
            });
            
            for (var i = 0; i < results.length; i++) {
              final msg = results[i];
              final distance = (msg['distance'] as num?)?.toDouble() ?? 0.0;
              final role = msg['role'] == 'user' ? 'ユーザー' : 'AI';
              final content = msg['content']?.toString() ?? '';
              final preview = content.length > 50 ? '${content.substring(0, 50)}...' : content;
              
              // 類似度を判定
              String similarity;
              if (distance < 0.3) {
                similarity = '🟢 高類似';
              } else if (distance < 0.6) {
                similarity = '🟡 中類似';
              } else {
                similarity = '🔴 低類似';
              }
              
              print('  ${i + 1}. $similarity [距離: ${distance.toStringAsFixed(4)}] $role: $preview');
            }
            
            // 一番近いメッセージの詳細
            if (results.isNotEmpty) {
              final closest = results.first;
              final closestDistance = (closest['distance'] as num?)?.toDouble() ?? 0.0;
              print('');
              print('🎯 最近傍メッセージ:');
              print('   距離: ${closestDistance.toStringAsFixed(6)}');
              print('   内容: ${closest['content']}');
            }
          }
          
          return results;
        } else {
          print('⚠️ ベクトル検索: API応答エラー');
        }
      } else {
        print('⚠️ ベクトル検索: HTTPエラー ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ ベクトル検索エラー: $e');
    }
    return [];
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
      // ベクトル検索で類似した過去の会話を取得
      final similarMessages = await _getSimilarMessages(text);
      
      // 類似メッセージをコンテキストとして追加
      String contextPrompt = '';
      if (similarMessages.isNotEmpty) {
        print('💡 コンテキスト追加: ${similarMessages.length}件の過去の会話を参照');
        contextPrompt = '\n\n過去の関連する会話:\n';
        for (var msg in similarMessages) {
          contextPrompt += '- ${msg['role']}: ${msg['content']}\n';
        }
        contextPrompt += '\n上記の過去の会話を参考にして、文脈に沿った返答をしてください。';
      } else {
        print('💡 コンテキスト追加: なし（通常の会話として処理）');
      }
      // 会話履歴を構築
      final conversationHistory = _messages.map((msg) {
        return {
          'role': msg.role == MessageRole.user ? 'user' : 'assistant',
          'content': msg.content,
        };
      }).toList();

      // システムプロンプトにコンテキストを追加
      final enhancedSystemPrompt = _systemPrompt + contextPrompt;

      // Azure OpenAI にリクエスト
      final response = await _azureService.sendChatMessage(
        messages: conversationHistory,
        systemPrompt: enhancedSystemPrompt,
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
      // ベクトル検索で類似した過去の会話を取得
      final similarMessages = await _getSimilarMessages(text);
      
      // 類似メッセージをコンテキストとして追加
      String contextPrompt = '';
      if (similarMessages.isNotEmpty) {
        print('💡 コンテキスト追加: ${similarMessages.length}件の過去の会話を参照');
        contextPrompt = '\n\n過去の関連する会話:\n';
        for (var msg in similarMessages) {
          contextPrompt += '- ${msg['role']}: ${msg['content']}\n';
        }
        contextPrompt += '\n上記の過去の会話を参考にして、文脈に沿った返答をしてください。';
      } else {
        print('💡 コンテキスト追加: なし（通常の会話として処理）');
      }
      // 会話履歴を構築
      final conversationHistory = _messages.where((msg) => 
        msg != assistantMessage // まだ空のアシスタントメッセージは除外
      ).map((msg) {
        return {
          'role': msg.role == MessageRole.user ? 'user' : 'assistant',
          'content': msg.content,
        };
      }).toList();

      // システムプロンプトにコンテキストを追加
      final enhancedSystemPrompt = _systemPrompt + contextPrompt;

      // ストリーミングでレスポンスを受け取る
      await for (final chunk in _azureService.sendChatMessageStream(
        messages: conversationHistory,
        systemPrompt: enhancedSystemPrompt,
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
