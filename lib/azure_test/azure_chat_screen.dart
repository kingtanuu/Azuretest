// lib/azure_test/azure_chat_screen.dart
/// Azure OpenAI を使用したチャット画面

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'azure_chat_controller.dart';
import 'models.dart';
import 'auth_controller.dart';

class AzureChatScreen extends StatefulWidget {
  const AzureChatScreen({super.key});

  @override
  State<AzureChatScreen> createState() => _AzureChatScreenState();
}

class _AzureChatScreenState extends State<AzureChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AzureChatController(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Azure OpenAI チャット'),
          actions: [
            // ログアウトボタン
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await SimpleAuthController().signOut();
                if (context.mounted) {
                  Navigator.of(context).pushReplacementNamed('/');
                }
              },
              tooltip: 'ログアウト',
            ),
            // システムプロンプト設定ボタン
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => _showSystemPromptDialog(context),
            ),
            // 会話クリアボタン
            Consumer<AzureChatController>(
              builder: (context, controller, _) {
                return IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: controller.messages.isEmpty
                      ? null
                      : () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('会話をクリア'),
                              content: const Text('会話履歴を削除しますか？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('キャンセル'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    controller.clearMessages();
                                    Navigator.pop(context);
                                  },
                                  child: const Text('削除'),
                                ),
                              ],
                            ),
                          );
                        },
                );
              },
            ),
          ],
        ),
        body: Consumer<AzureChatController>(
          builder: (context, controller, _) {
            // メッセージが更新されたら自動スクロール
            if (controller.messages.isNotEmpty) {
              _scrollToBottom();
            }

            return Column(
              children: [
                // エラーメッセージ表示
                if (controller.errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.red[100],
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            controller.errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: controller.clearError,
                        ),
                      ],
                    ),
                  ),

                // メッセージリスト
                Expanded(
                  child: controller.messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'メッセージを送信して会話を始めましょう',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: controller.messages.length,
                          itemBuilder: (context, index) {
                            final message = controller.messages[index];
                            return _MessageBubble(message: message);
                          },
                        ),
                ),

                // ローディングインジケーター
                if (controller.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        SizedBox(width: 16),
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('応答を生成中...'),
                      ],
                    ),
                  ),

                // 入力エリア
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          decoration: const InputDecoration(
                            hintText: 'メッセージを入力...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: controller.isLoading
                              ? null
                              : (text) {
                                  if (text.trim().isNotEmpty) {
                                    // ストリーミング版を使用
                                    controller.sendMessageStream(text);
                                    _textController.clear();
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: controller.isLoading
                            ? null
                            : () {
                                final text = _textController.text;
                                if (text.trim().isNotEmpty) {
                                  // ストリーミング版を使用
                                  controller.sendMessageStream(text);
                                  _textController.clear();
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showSystemPromptDialog(BuildContext context) {
    final controller = Provider.of<AzureChatController>(context, listen: false);
    final textController = TextEditingController(text: controller.systemPrompt);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('システムプロンプト設定'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'AIの振る舞いを指定...',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              controller.systemPrompt = textController.text;
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

/// メッセージバブルウィジェット
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: Colors.blue[100],
              child: const Icon(Icons.smart_toy, color: Colors.blue),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue[500] : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.grey[300],
              child: const Icon(Icons.person, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}
