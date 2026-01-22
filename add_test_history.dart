import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'lib/firebase_options.dart';

void main() async {
  // Firebaseを初期化
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final firestore = FirebaseFirestore.instance;
  final userId = 'vULtRLX0jtbS6hBUqwN6hoRa2dp2';

  // 3日前のデータ
  final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
  final date3 = '${threeDaysAgo.year}${threeDaysAgo.month.toString().padLeft(2, '0')}${threeDaysAgo.day.toString().padLeft(2, '0')}';
  
  await firestore
      .collection('users')
      .doc(userId)
      .collection('chat')
      .doc('allchat_$date3')
      .set({
    'date': date3,
    'createdAt': FieldValue.serverTimestamp(),
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
    'updatedAt': FieldValue.serverTimestamp(),
  });

  print('✅ 3日前のチャット履歴を追加しました: allchat_$date3');

  // 5日前のデータ
  final fiveDaysAgo = DateTime.now().subtract(const Duration(days: 5));
  final date5 = '${fiveDaysAgo.year}${fiveDaysAgo.month.toString().padLeft(2, '0')}${fiveDaysAgo.day.toString().padLeft(2, '0')}';
  
  await firestore
      .collection('users')
      .doc(userId)
      .collection('chat')
      .doc('allchat_$date5')
      .set({
    'date': date5,
    'createdAt': FieldValue.serverTimestamp(),
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
    'updatedAt': FieldValue.serverTimestamp(),
  });

  print('✅ 5日前のチャット履歴を追加しました: allchat_$date5');
  print('✅ テストデータの追加が完了しました！');
}
