import * as admin from "firebase-admin";
import {setGlobalOptions} from "firebase-functions";
import {onRequest} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import axios from "axios";

admin.initializeApp();
const db = admin.firestore();

const OPENAI_API_URL = "https://api.openai.com/v1/embeddings";
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || "";

setGlobalOptions({maxInstances: 10});

// OpenAI APIコールとベクトル取得の共通関数
const getVectorEmbeddedText = async (text: string) => {
  const response = await axios.post(
    OPENAI_API_URL,
    {model: "text-embedding-3-small", input: text},
    {
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
    }
  );
  return response.data.data[0].embedding;
};

/* 最近傍クエリを実行する関数（CORS設定）*/
export const getNearestNeighbor = onRequest(
  {cors: true, secrets: ["OPENAI_API_KEY"]},
  async (req, res) => {
    try {
    // GETリクエストのクエリからテキストとユーザーIDを取得
      const text = req.query.text;
      const userId = req.query.userId;

      if (typeof text !== "string" || typeof userId !== "string") {
        res.status(400).json({
          error:
          "Invalid request: 'text' and 'userId' query parameters " +
          "are required.",
        });
        return;
      }

      logger.info(`Vector search for user ${userId}: ${text}`);

      // ベクトル化されたデータを取得
      const embedding = await getVectorEmbeddedText(text);

      // embeddingからFieldValue.vectorを生成
      const vector = admin.firestore.FieldValue.vector(embedding);

      // まず、users/{userId}/chats サブコレクションにデータが存在するか確認
      logger.info(
        `Searching in path: users/${userId}/chats/*/messages/`,
      );

      // デバッグ: 実際に保存されているメッセージ数を確認
      const userChatsRef = db.collection("users")
        .doc(userId).collection("chats");
      const chatsSnapshot = await userChatsRef.get();
      logger.info(
        `User has ${chatsSnapshot.docs.length} chat documents`,
      );

      // 各チャットドキュメントのメッセージ数を確認
      for (const chatDoc of chatsSnapshot.docs) {
        const messagesSnapshot = await
        chatDoc.ref.collection("messages").get();
        logger.info(
          `  ${chatDoc.id}: ${messagesSnapshot.docs.length} messages`,
        );
        if (messagesSnapshot.docs.length > 0) {
          const firstMsg = messagesSnapshot.docs[0].data();
          const content = firstMsg.content?.substring(0, 30);
          logger.info(
            `    Sample: hasEmbedding=${!!firstMsg.embedding_field}, `+
            `content="${content}..."`,
          );
        }
      }

      // 🔍 全メッセージ数をカウント（デバッグ用）
      const allMessages = await db.collectionGroup("messages").get();
      logger.info(
        `📊 Total messages in entire Firestore: ${allMessages.size}`,
      );

      // 🔍 最初の3件のメッセージパスを表示
      allMessages.docs.slice(0, 3).forEach((doc) => {
        const data = doc.data();
        const embField = data.embedding_field;
        logger.info(
          `  Sample path: ${doc.ref.path}, ` +
          `embedding_field: ${embField ?
            `array[${embField.length}]` : "missing"}`,
        );
      });

      // ベクトル検索
      // where句なし - クライアント側でuserIdフィルタリングを行う
      const vectorQuery = db.collectionGroup("messages")
        .findNearest({
          limit: 50, // フィルタリング後に十分な結果を得るため多めに取得
          distanceMeasure: "COSINE",
          vectorField: "embedding_field",
          queryVector: vector,
          distanceResultField: "vector_distance", // 距離をデータ内に保存
        });

      const snapshot = await vectorQuery.get();

      logger.info(
        `Vector query returned ${snapshot.docs.length} docs before filtering`,
      );

      // デバッグ: 最初の数件のドキュメント情報をログ出力
      if (snapshot.docs.length > 0) {
        logger.info("Sample documents from findNearest:");
        snapshot.docs.slice(0, 5).forEach((doc, index) => {
          const data = doc.data();
          const content = data.content?.substring(0, 30);
          logger.info(
            `  Doc ${index}: path="${doc.ref.path}", ` +
            `userId="${data.userId}", ` +
            `content="${content}...", ` +
            `hasEmbedding=${!!data.embedding_field}`,
          );
        });
        logger.info(`Target userId for filtering: "${userId}"`);
      } else {
        logger.warn(
          "⚠️ Vector query returned 0 documents - " +
          "check if embedding_field exists in Firestore",
        );
      }

      // クライアント側でuserIdフィルタリング
      const filteredDocs = snapshot.docs.filter((doc) => {
        const docUserId = doc.data().userId;
        const matches = docUserId === userId;
        if (!matches && snapshot.docs.length < 10) {
          // 少数の場合は不一致の理由をログ
          logger.info(`  Filtered out: userId="${docUserId}" ` +
            `vs target="${userId}"`);
        }
        return matches;
      });

      logger.info(
        `After userId filter: ${filteredDocs.length} docs`,
      );

      // 最も近い5件のみを使用
      const limitedDocs = filteredDocs.slice(0, 5);

      // レスポンスを構築
      const results = limitedDocs.map((doc) => {
        const data = doc.data();
        // distanceResultField で保存された距離を取得
        const distance = typeof data.vector_distance === "number" ?
          data.vector_distance : null;
        return {
          id: doc.id,
          role: data.role,
          content: data.content,
          timestamp: data.timestamp?.toDate?.()?.toISOString() || null,
          distance,
        };
      });

      logger.info(`Found ${results.length} similar messages`);
      res.status(200).json({success: true, results});
    } catch (error) {
      logger.error("Error in vector search:", error);
      res.status(500).json({error: "Error searching vectors."});
    }
  });
