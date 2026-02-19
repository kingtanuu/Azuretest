"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getNearestNeighbor = void 0;
const admin = __importStar(require("firebase-admin"));
const firebase_functions_1 = require("firebase-functions");
const https_1 = require("firebase-functions/https");
const logger = __importStar(require("firebase-functions/logger"));
const axios_1 = __importDefault(require("axios"));
admin.initializeApp();
const db = admin.firestore();
const OPENAI_API_URL = "https://api.openai.com/v1/embeddings";
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || "";
(0, firebase_functions_1.setGlobalOptions)({ maxInstances: 10 });
// OpenAI APIコールとベクトル取得の共通関数
const getVectorEmbeddedText = async (text) => {
    const response = await axios_1.default.post(OPENAI_API_URL, { model: "text-embedding-3-small", input: text }, {
        headers: {
            "Authorization": `Bearer ${OPENAI_API_KEY}`,
            "Content-Type": "application/json",
        },
    });
    return response.data.data[0].embedding;
};
/* 最近傍クエリを実行する関数（CORS設定）*/
exports.getNearestNeighbor = (0, https_1.onRequest)({ cors: true, secrets: ["OPENAI_API_KEY"] }, async (req, res) => {
    var _a;
    try {
        // GETリクエストのクエリからテキストとユーザーIDを取得
        const text = req.query.text;
        const userId = req.query.userId;
        if (typeof text !== "string" || typeof userId !== "string") {
            res.status(400).json({
                error: "Invalid request: 'text' and 'userId' query parameters " +
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
        logger.info(`Searching in path: users/${userId}/chats/*/messages/`);
        // デバッグ: 実際に保存されているメッセージ数を確認
        const userChatsRef = db.collection("users")
            .doc(userId).collection("chats");
        const chatsSnapshot = await userChatsRef.get();
        logger.info(`User has ${chatsSnapshot.docs.length} chat documents`);
        // 各チャットドキュメントのメッセージ数を確認
        for (const chatDoc of chatsSnapshot.docs) {
            const messagesSnapshot = await chatDoc.ref.collection("messages").get();
            logger.info(`  ${chatDoc.id}: ${messagesSnapshot.docs.length} messages`);
            if (messagesSnapshot.docs.length > 0) {
                const firstMsg = messagesSnapshot.docs[0].data();
                const content = (_a = firstMsg.content) === null || _a === void 0 ? void 0 : _a.substring(0, 30);
                logger.info(`    Sample: hasEmbedding=${!!firstMsg.embedding_field}, ` +
                    `content="${content}..."`);
            }
        }
        // 🔍 全メッセージ数をカウント（デバッグ用）
        const allMessages = await db.collectionGroup("messages").get();
        logger.info(`📊 Total messages in entire Firestore: ${allMessages.size}`);
        // 🔍 最初の3件のメッセージパスを表示
        allMessages.docs.slice(0, 3).forEach((doc) => {
            const data = doc.data();
            const embField = data.embedding_field;
            logger.info(`  Sample path: ${doc.ref.path}, ` +
                `embedding_field: ${embField ?
                    `array[${embField.length}]` : "missing"}`);
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
        logger.info(`Vector query returned ${snapshot.docs.length} docs before filtering`);
        // デバッグ: 最初の数件のドキュメント情報をログ出力
        if (snapshot.docs.length > 0) {
            logger.info("Sample documents from findNearest:");
            snapshot.docs.slice(0, 5).forEach((doc, index) => {
                var _a;
                const data = doc.data();
                const content = (_a = data.content) === null || _a === void 0 ? void 0 : _a.substring(0, 30);
                logger.info(`  Doc ${index}: path="${doc.ref.path}", ` +
                    `userId="${data.userId}", ` +
                    `content="${content}...", ` +
                    `hasEmbedding=${!!data.embedding_field}`);
            });
            logger.info(`Target userId for filtering: "${userId}"`);
        }
        else {
            logger.warn("⚠️ Vector query returned 0 documents - " +
                "check if embedding_field exists in Firestore");
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
        logger.info(`After userId filter: ${filteredDocs.length} docs`);
        // 最も近い5件のみを使用
        const limitedDocs = filteredDocs.slice(0, 5);
        // レスポンスを構築
        const results = limitedDocs.map((doc) => {
            var _a, _b, _c;
            const data = doc.data();
            // distanceResultField で保存された距離を取得
            const distance = typeof data.vector_distance === "number" ?
                data.vector_distance : null;
            return {
                id: doc.id,
                role: data.role,
                content: data.content,
                timestamp: ((_c = (_b = (_a = data.timestamp) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) === null || _c === void 0 ? void 0 : _c.toISOString()) || null,
                distance,
            };
        });
        logger.info(`Found ${results.length} similar messages`);
        res.status(200).json({ success: true, results });
    }
    catch (error) {
        logger.error("Error in vector search:", error);
        res.status(500).json({ error: "Error searching vectors." });
    }
});
//# sourceMappingURL=index.js.map