// lib/azure_test/azure_openai_service.dart
/// Azure OpenAI Service との連携を行うサービス

import 'dart:convert';
import 'package:http/http.dart' as http;

class AzureOpenAIService {
  // Azure OpenAI の設定
  static const String _endpoint = 'https://fintuning-test.cognitiveservices.azure.com';
  // APIキーは環境変数から取得（セキュリティのため）
  static const String _apiKey = String.fromEnvironment('AZURE_OPENAI_API_KEY', 
    defaultValue: 'CMyjcU1FyXKkYehfCsjChk0AxCuMCpVUZN1wOcwhv60D2Jwf5KpaJQQJ99CBACi0881XJ3w3AAAAACOGQkG7');
  static const String _deployment = 'gpt-4.1-mini';
  static const String _apiVersion = '2025-01-01-preview';

  /// チャットメッセージを送信して応答を取得
  /// 
  /// [messages] 会話履歴を含むメッセージリスト
  /// [systemPrompt] システムプロンプト（オプション）
  /// [temperature] 応答のランダム性（0.0-2.0、デフォルト: 1.0）
  /// [maxTokens] 最大トークン数（デフォルト: 13107）
  Future<String> sendChatMessage({
    required List<Map<String, String>> messages,
    String? systemPrompt,
    double temperature = 1.0,
    int maxTokens = 13107,
  }) async {
    try {
      // システムプロンプトを先頭に追加
      final List<Map<String, String>> fullMessages = [];
      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        fullMessages.add({
          'role': 'system',
          'content': systemPrompt,
        });
      }
      fullMessages.addAll(messages);

      // リクエストURL
      final url = Uri.parse(
        '$_endpoint/openai/deployments/$_deployment/chat/completions?api-version=$_apiVersion',
      );

      // リクエストボディ
      final body = jsonEncode({
        'messages': fullMessages,
        'temperature': temperature,
        'max_completion_tokens': maxTokens,
        'top_p': 1.0,
        'frequency_penalty': 0.0,
        'presence_penalty': 0.0,
      });

      // APIリクエスト
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'api-key': _apiKey,
        },
        body: body,
      );

      // レスポンスの処理
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (data['choices'] != null && data['choices'].isNotEmpty) {
          return data['choices'][0]['message']['content'] as String;
        } else {
          throw Exception('応答にメッセージが含まれていません');
        }
      } else {
        final errorData = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(
          'Azure OpenAI API エラー (${response.statusCode}): ${errorData['error']?['message'] ?? '不明なエラー'}',
        );
      }
    } catch (e) {
      print('Azure OpenAI Service エラー: $e');
      rethrow;
    }
  }

  /// ストリーミング形式でチャットメッセージを送信
  /// 
  /// [messages] 会話履歴を含むメッセージリスト
  /// [systemPrompt] システムプロンプト（オプション）
  /// [temperature] 応答のランダム性（0.0-2.0、デフォルト: 1.0）
  /// [maxTokens] 最大トークン数（デフォルト: 13107）
  /// 
  /// 戻り値: チャンクごとのテキストを返すStream
  Stream<String> sendChatMessageStream({
    required List<Map<String, String>> messages,
    String? systemPrompt,
    double temperature = 1.0,
    int maxTokens = 13107,
  }) async* {
    try {
      // システムプロンプトを先頭に追加
      final List<Map<String, String>> fullMessages = [];
      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        fullMessages.add({
          'role': 'system',
          'content': systemPrompt,
        });
      }
      fullMessages.addAll(messages);

      // リクエストURL
      final url = Uri.parse(
        '$_endpoint/openai/deployments/$_deployment/chat/completions?api-version=$_apiVersion',
      );

      // リクエストボディ（ストリーミング有効）
      final body = jsonEncode({
        'messages': fullMessages,
        'temperature': temperature,
        'max_completion_tokens': maxTokens,
        'top_p': 1.0,
        'frequency_penalty': 0.0,
        'presence_penalty': 0.0,
        'stream': true, // ストリーミングを有効化
      });

      // HTTPリクエスト（ストリーミング）
      final request = http.Request('POST', url);
      request.headers.addAll({
        'Content-Type': 'application/json',
        'api-key': _apiKey,
      });
      request.body = body;

      final streamedResponse = await request.send();

      if (streamedResponse.statusCode == 200) {
        // ストリームを処理
        await for (var chunk in streamedResponse.stream.transform(utf8.decoder)) {
          // Server-Sent Events (SSE) 形式のデータを解析
          final lines = chunk.split('\n');
          for (var line in lines) {
            if (line.startsWith('data: ')) {
              final data = line.substring(6).trim();
              
              // [DONE] シグナルをチェック
              if (data == '[DONE]') {
                break;
              }
              
              try {
                final json = jsonDecode(data);
                final content = json['choices']?[0]?['delta']?['content'];
                if (content != null && content.isNotEmpty) {
                  yield content as String;
                }
              } catch (e) {
                // JSONパースエラーは無視（不完全なチャンクの可能性）
                continue;
              }
            }
          }
        }
      } else {
        final errorBody = await streamedResponse.stream.bytesToString();
        final errorData = jsonDecode(errorBody);
        throw Exception(
          'Azure OpenAI API エラー (${streamedResponse.statusCode}): ${errorData['error']?['message'] ?? '不明なエラー'}',
        );
      }
    } catch (e) {
      print('Azure OpenAI Service ストリーミングエラー: $e');
      rethrow;
    }
  }

  /// 簡易的な会話メソッド（単一のメッセージを送信）
  /// 
  /// [userMessage] ユーザーのメッセージ
  /// [systemPrompt] システムプロンプト（オプション）
  Future<String> chat({
    required String userMessage,
    String? systemPrompt,
  }) async {
    return await sendChatMessage(
      messages: [
        {'role': 'user', 'content': userMessage},
      ],
      systemPrompt: systemPrompt,
    );
  }
}
