// lib/azure_test/chat_history_service.dart
/// Firestoreを使ってチャット履歴を管理するサービス

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models.dart';

class ChatHistoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 現在のユーザーIDを取得
  String? get _userId => _auth.currentUser?.uid;

  /// チャットセッションを作成
  /// 
  /// [title] セッションのタイトル（オプション、デフォルトは日時）
  /// 戻り値: 作成されたセッションID
  Future<String> createChatSession({String? title}) async {
    if (_userId == null) throw Exception('ユーザーが認証されていません');

    final now = DateTime.now();
    final sessionTitle = title ?? '会話 ${now.year}/${now.month}/${now.day} ${now.hour}:${now.minute}';

    final docRef = await _firestore
        .collection('users')
        .doc(_userId)
        .collection('chat_sessions')
        .add({
      'title': sessionTitle,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'message_count': 0,
    });

    return docRef.id;
  }

  /// チャットメッセージを保存
  /// 
  /// [sessionId] セッションID
  /// [message] 保存するメッセージ
  Future<void> saveMessage(String sessionId, ChatMessage message) async {
    if (_userId == null) throw Exception('ユーザーが認証されていません');

    // メッセージを保存
    await _firestore
        .collection('users')
        .doc(_userId)
        .collection('chat_sessions')
        .doc(sessionId)
        .collection('messages')
        .add({
      'role': message.role,
      'content': message.content,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // セッションの更新日時とメッセージ数を更新
    await _firestore
        .collection('users')
        .doc(_userId)
        .collection('chat_sessions')
        .doc(sessionId)
        .update({
      'updated_at': FieldValue.serverTimestamp(),
      'message_count': FieldValue.increment(1),
    });
  }

  /// セッションのメッセージ履歴を取得
  /// 
  /// [sessionId] セッションID
  /// 戻り値: メッセージのリスト
  Future<List<ChatMessage>> getMessages(String sessionId) async {
    if (_userId == null) throw Exception('ユーザーが認証されていません');

    final snapshot = await _firestore
        .collection('users')
        .doc(_userId)
        .collection('chat_sessions')
        .doc(sessionId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return ChatMessage(
        role: data['role'] as String,
        content: data['content'] as String,
      );
    }).toList();
  }

  /// ユーザーのチャットセッション一覧を取得
  /// 
  /// 戻り値: セッション情報のリスト（ID、タイトル、更新日時、メッセージ数）
  Stream<List<Map<String, dynamic>>> getChatSessions() {
    if (_userId == null) throw Exception('ユーザーが認証されていません');

    return _firestore
        .collection('users')
        .doc(_userId)
        .collection('chat_sessions')
        .orderBy('updated_at', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'title': data['title'] as String,
          'created_at': data['created_at'] as Timestamp?,
          'updated_at': data['updated_at'] as Timestamp?,
          'message_count': data['message_count'] as int? ?? 0,
        };
      }).toList();
    });
  }

  /// チャットセッションを削除
  /// 
  /// [sessionId] 削除するセッションID
  Future<void> deleteSession(String sessionId) async {
    if (_userId == null) throw Exception('ユーザーが認証されていません');

    // メッセージを全て削除
    final messagesSnapshot = await _firestore
        .collection('users')
        .doc(_userId)
        .collection('chat_sessions')
        .doc(sessionId)
        .collection('messages')
        .get();

    for (var doc in messagesSnapshot.docs) {
      await doc.reference.delete();
    }

    // セッションを削除
    await _firestore
        .collection('users')
        .doc(_userId)
        .collection('chat_sessions')
        .doc(sessionId)
        .delete();
  }

  /// セッションのタイトルを更新
  /// 
  /// [sessionId] セッションID
  /// [newTitle] 新しいタイトル
  Future<void> updateSessionTitle(String sessionId, String newTitle) async {
    if (_userId == null) throw Exception('ユーザーが認証されていません');

    await _firestore
        .collection('users')
        .doc(_userId)
        .collection('chat_sessions')
        .doc(sessionId)
        .update({
      'title': newTitle,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }
}
