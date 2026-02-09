# Mutimon Chat Application

Azure OpenAI と Firebase を使用したシンプルなチャットアプリケーション

## 📁 プロジェクト構造

```
lib/
  mutimon_chat/               # アプリケーションルート
    v1/                       # APIバージョン v1
      auth/                   # 認証機能
        auth_controller.dart  # 認証ロジック
        login_screen.dart     # ログイン画面
      chat/                   # チャット機能
        chat_controller.dart  # チャットロジック
        chat_screen.dart      # チャット画面
        openai_service.dart   # Azure OpenAI連携
      models/                 # データモデル
        models.dart           # メッセージ等のモデル定義
      firebase_options.dart   # Firebase設定
      main.dart               # エントリーポイント
```

### ディレクトリ設計の考え方

- **ルート階層 (`mutimon_chat/`)**: アプリケーション名
- **第一階層 (`v1/`)**: APIバージョン管理（将来の改変に対応）
- **第二階層 (`auth/`, `chat/`, `models/`)**: 機能ごとにディレクトリを分割
- **第三階層**: 単一機能のロジック実装（関数の切り分けを意識）

## 🚀 セットアップ

### 必要な環境

- Flutter SDK 3.0.0 以上
- Dart SDK 3.0.0 以上
- Firebase プロジェクト
- Azure OpenAI アカウント

### 1. 依存パッケージのインストール

```bash
flutter pub get
```

### 2. Firebase の設定

1. Firebase Console でプロジェクトを作成
2. Flutterfire CLI で設定ファイルを生成：

```bash
flutterfire configure
```

3. 以下のサービスを有効化：
   - **Firebase Authentication** (メール/パスワード認証)
   - **Cloud Firestore** (メッセージ保存)
   - **Firebase Storage** (将来の拡張用)

### 3. Firestore セキュリティルールの設定

Firebase Console で以下のルールを設定：

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### 4. Azure OpenAI の設定

1. Azure Portal で OpenAI リソースを作成
2. デプロイメントを作成（推奨: gpt-4）
3. API キーとエンドポイントを取得
4. `lib/mutimon_chat/v1/chat/openai_service.dart` の以下を更新：

```dart
static const String _endpoint = 'https://your-resource.cognitiveservices.azure.com';
static const String _deployment = 'your-deployment-name';
```

## 📱 実行方法

### Web（Chrome）で実行

```bash
flutter run -t lib/mutimon_chat/v1/main.dart -d chrome \
  --dart-define=AZURE_OPENAI_API_KEY=your_api_key_here
```

### その他のプラットフォーム

```bash
# iOS
flutter run -t lib/mutimon_chat/v1/main.dart -d ios \
  --dart-define=AZURE_OPENAI_API_KEY=your_api_key_here

# Android
flutter run -t lib/mutimon_chat/v1/main.dart -d android \
  --dart-define=AZURE_OPENAI_API_KEY=your_api_key_here

# macOS
flutter run -t lib/mutimon_chat/v1/main.dart -d macos \
  --dart-define=AZURE_OPENAI_API_KEY=your_api_key_here
```

## 🔐 セキュリティ

- **API キーの管理**: 
  - `--dart-define` で環境変数として渡す
  - ソースコードに直接書き込まない
  - `.gitignore` に API キーを含むファイルを追加

- **Firebase ルール**: 
  - ユーザーは自分のデータのみアクセス可能
  - 認証必須

## 📚 機能

### v1 の機能

- ✅ Firebase Authentication によるログイン/ログアウト
- ✅ Azure OpenAI とのチャット
- ✅ メッセージの Firestore への自動保存
- ✅ ストリーミングレスポンス対応
- ✅ システムプロンプトのカスタマイズ
- ✅ 会話履歴のクリア

### データ保存構造

Firestore にメッセージを以下の形式で保存：

```
users/
  {userId}/
    chats/
      chat_YYYYMMDD/
        messages/
          {messageId}/
            role: "user" | "assistant"
            content: string
            timestamp: Timestamp
```

## 🛠 開発

### コードの修正

1. 機能追加時は適切なディレクトリに配置
2. 単一責任の原則に従って関数を分割
3. コメントで機能を明確に記述

### ビルド

```bash
# Web
flutter build web -t lib/mutimon_chat/v1/main.dart \
  --dart-define=AZURE_OPENAI_API_KEY=your_api_key_here

# iOS
flutter build ios -t lib/mutimon_chat/v1/main.dart \
  --dart-define=AZURE_OPENAI_API_KEY=your_api_key_here

# Android
flutter build apk -t lib/mutimon_chat/v1/main.dart \
  --dart-define=AZURE_OPENAI_API_KEY=your_api_key_here
```

## 📝 ライセンス

このプロジェクトは内部使用を目的としています。

## 🤝 貢献

バグ報告や機能リクエストは Issue で受け付けています。

## 📞 サポート

問題が発生した場合は、以下を確認してください：

1. Flutter SDK のバージョン
2. Firebase の設定
3. Azure OpenAI の API キーとエンドポイント
4. ターミナルのエラーメッセージ
