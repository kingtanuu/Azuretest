# Firestore テストデータ追加手順

## Firebaseコンソールでの手動追加

1. Firebase Console にアクセス: https://console.firebase.google.com/project/azuretest-18970/firestore

2. Firestore Database > データ タブを開く

3. パス: `users/vULtRLX0jtbS6hBUqwN6hoRa2dp2/chat` を開く

## ドキュメント1: 3日前のマラソンの会話 (allchat_20260119)

**ドキュメントID**: `allchat_20260119`

**フィールド**:
- `date` (string): `20260119`
- `createdAt` (timestamp): 自動
- `updatedAt` (timestamp): 自動
- `messages` (array):
  ```
  [
    {
      role: "user",
      content: "最近マラソンを始めました！",
      timestamp: 2026-01-19 12:00:00
    },
    {
      role: "assistant",
      content: "マラソンを始めたんですね！素晴らしいです。健康的な趣味ですね。どれくらいの距離を走っていますか？",
      timestamp: 2026-01-19 12:00:05
    },
    {
      role: "user",
      content: "週に3回、5キロくらい走っています",
      timestamp: 2026-01-19 12:01:00
    },
    {
      role: "assistant",
      content: "週3回で5キロとは良いペースですね！継続が大切です。フルマラソンに挑戦する予定はありますか？",
      timestamp: 2026-01-19 12:01:05
    }
  ]
  ```

## ドキュメント2: 5日前の野球の会話 (allchat_20260117)

**ドキュメントID**: `allchat_20260117`

**フィールド**:
- `date` (string): `20260117`
- `createdAt` (timestamp): 自動
- `updatedAt` (timestamp): 自動
- `messages` (array):
  ```
  [
    {
      role: "user",
      content: "野球観戦が好きで、よく球場に行きます",
      timestamp: 2026-01-17 14:00:00
    },
    {
      role: "assistant",
      content: "野球観戦が趣味なんですね！どこのチームのファンですか？球場で見る野球は臨場感がありますよね。",
      timestamp: 2026-01-17 14:00:05
    },
    {
      role: "user",
      content: "ジャイアンツファンです！",
      timestamp: 2026-01-17 14:01:00
    },
    {
      role: "assistant",
      content: "読売ジャイアンツのファンなんですね！伝統のあるチームです。東京ドームにはよく行かれますか？",
      timestamp: 2026-01-17 14:01:05
    }
  ]
  ```

## 追加後の確認方法

1. アプリをリロード (Cmd+R)
2. コンソールで「会話履歴読み込み完了: X件」を確認
3. マラソンや野球について質問すると、AIが過去の会話を参照して回答するはず
