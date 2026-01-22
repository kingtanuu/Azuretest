// lib/azure_test/models.dart
/// チャット機能のデータモデル

/// チャットメッセージのデータクラス
class ChatMessage {
  final MessageRole role;
  String content;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });
}

/// メッセージの役割（ユーザーまたはアシスタント）
enum MessageRole {
  user,
  assistant,
}
