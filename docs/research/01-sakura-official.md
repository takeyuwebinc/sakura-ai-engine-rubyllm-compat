# Sakura AI Engine 公式情報サマリ

- **最終確認日**: 2026-05-09
- **対象**: さくらインターネット「さくらのAI Engine」（`https://api.ai.sakura.ad.jp/v1`）
- **目的**: RubyLLM v1.x と組み合わせる際の互換性の境界（公式が「明示しているか／いないか」）を一次情報から確定する
- **調査者注**: 本ドキュメントは「公式が明示している事実」のみを記録する。実機挙動は別調査で検証する。

---

## 0. 一次情報源（出典 URL 一覧）

| # | 種類 | URL | 取得状況 |
|---|---|---|---|
| S1 | 公式マニュアル トップ | https://manual.sakura.ad.jp/cloud/manual-ai-engine.html | OK |
| S2 | サービス基本情報 | https://manual.sakura.ad.jp/cloud/ai-engine/01-basics.html | OK |
| S3 | 利用手順 | https://manual.sakura.ad.jp/cloud/ai-engine/02-howto.html | OK |
| S4 | Playground | https://manual.sakura.ad.jp/cloud/ai-engine/playground.html | OK |
| S5 | 操作ガイド | https://manual.sakura.ad.jp/cloud/ai-engine/03-operation-guide.html | OK |
| S6 | 提供モデルのライセンス表示 | https://manual.sakura.ad.jp/cloud/ai-engine/04-licenses.html | OK |
| S7 | 音声合成モデルのライセンス | https://manual.sakura.ad.jp/cloud/ai-engine/05-tts-licenses.html | OK |
| S8 | クローズドモデルの利用に関して | https://manual.sakura.ad.jp/cloud/ai-engine/06-closed-model.html | OK |
| S9 | Inference API リファレンス（Redoc レンダラ） | https://manual.sakura.ad.jp/api/cloud/ai-engine/inference.html | OK（HTML はクライアントレンダリング） |
| S10 | **Inference API OpenAPI 仕様（実体）** | https://manual.sakura.ad.jp/api/cloud/portal/assets/ai-engine-inference-BqRm7_0x.yaml | OK（Redoc バンドルから抽出） |
| S11 | RAG API OpenAPI 仕様 | https://manual.sakura.ad.jp/api/cloud/portal/assets/ai-engine-rag-bliJ6K45.yaml | OK |
| S12 | 公式サービス紹介 | https://www.sakura.ad.jp/aipf/ai-engine/ | OK |
| S13 | 公式ニュースリリース（GA 開始, 2025-09-24） | https://www.sakura.ad.jp/corporate/information/newsreleases/2025/09/24/1968221046/ | OK（一部文字化けあり） |
| Z1 | 公式 Zenn: HTTP ストリームを Postman でテスト | https://zenn.dev/sakura_internet/articles/a00e22f4e6cf57 | OK |
| Z2 | 公式 Zenn: Strands Agents 連携 (1) | https://zenn.dev/sakura_internet/articles/9154ac5556a6b9 | OK |
| Z3 | 公式 Zenn: DSPy サンプル | https://zenn.dev/sakura_internet/articles/90d7f91ef373b0 | OK |
| Z4 | 公式 Zenn: 技術トレンド記事読みアプリ | https://zenn.dev/sakura_internet/articles/ai-engine-kijiyomu | OK（コード抜粋は取得不可、GitHub 参照） |
| Z5 | 個人 Zenn: API 性能検証（公式ではない） | https://zenn.dev/kota_iizuka/articles/3fec86fb4a11b4 | OK（参考） |
| Z6 | 個人 Zenn: コーディングエージェント実験（公式ではない） | https://zenn.dev/kota_iizuka/articles/35250c57ae3cd4 | OK（参考） |

> **注意**: S10 / S11 は Redoc 用 bundle に埋め込まれた asset 名で取得した URL。バンドルが再ビルドされるとファイル名（hash 付き）が変わる可能性がある。再取得時は `https://manual.sakura.ad.jp/api/cloud/portal/assets/index-*.js` から `ai-engine-inference-*.yaml` / `ai-engine-rag-*.yaml` の参照を再抽出する必要がある。

---

## 1. エンドポイントと認証

### 1.1 ベース URL（出典: S3, S10, Z1）

- API ベース URL: **`https://api.ai.sakura.ad.jp`**
- chat completions: **`POST https://api.ai.sakura.ad.jp/v1/chat/completions`**
- OpenAPI `servers` 定義: `- url: https://api.ai.sakura.ad.jp`
- 公式ドキュメント／Zenn ともに `/v1` プレフィックスを一貫して使用

### 1.2 認証方式（出典: S3, S10）

- 方式: **Bearer Token**
  - HTTP ヘッダ: `Authorization: Bearer <Token>`
  - OpenAPI security scheme: `BearerAuth: { type: http, scheme: bearer }`
- トークン形式: `<UUID>:<シークレット>` のペア（S3 原文）
- 発行手順:
  1. コントロールパネル `https://secure.sakura.ad.jp/ai/` にアクセス
  2. プラン選択、利用規約同意
  3. 「アカウントトークン」メニュー →「アカウントトークンを作成」
  4. トークン名を入力して作成
- 重要警告（S3 原文）:
  > 「このトークンは再度表示されません。コピーして安全な場所に保存してください」

### 1.3 credentials の推奨される置き方

- 公式マニュアルには**具体的な格納推奨は記載されていない**（「安全な場所に保存」とのみ記述）。
- 公式 Zenn 記事（Z2: Strands Agents）では `client_args["api_key"]` に直接渡すサンプルのみで、Rails 規約への言及はない。
- Z6（個人記事）では `~/.qwen/.env` に `OPENAI_API_KEY=...` として置いている（参考、公式ではない）。
- **公式記載なし（Rails 標準の credentials.yml.enc 等の推奨は別調査）**。

### 1.4 curl サンプル（S3 原文ママ）

```bash
curl --location 'https://api.ai.sakura.ad.jp/v1/chat/completions' \
  --header 'Accept: application/json' \
  --header 'Authorization: Bearer <Token>' \
  --header 'Content-Type: application/json' \
  --data '{
    "model": "gpt-oss-120b",
    "messages": [
      { "role": "system", "content": "こんにちは！" }
    ],
    "temperature": 0.7,
    "max_tokens": 200,
    "stream": false
  }'
```

---

## 2. 提供モデル一覧

### 2.1 公式マニュアル「ライセンス表示」（S6, 2026-05-09 時点）に記載のモデル

| モデル名（API model 文字列） | 提供元 | ライセンス | 種別（推測） |
|---|---|---|---|
| `gpt-oss-120b` | OpenAI | Apache 2.0 | チャット（reasoning 系） |
| `llm-jp-3.1-8x13b-instruct4` | LLM-jp | Apache 2.0 | チャット（日本語特化 MoE） |
| `Qwen3-Coder-480B-A35B-Instruct-FP8` | Alibaba Cloud | Apache 2.0 | チャット（コード特化 MoE） |
| `Qwen3-Coder-30B-A3B-Instruct` | Alibaba Cloud | Apache 2.0 | チャット（コード特化 MoE 小型） |
| `Qwen3-0.6B` | Alibaba Cloud | Apache 2.0 | チャット（極小型） |
| `Qwen3-VL-30B-A3B-Instruct` | Alibaba Cloud | Apache 2.0 | チャット（Vision） |
| `Qwen3-Embedding-4B` | Alibaba Cloud | Apache 2.0 | embeddings |
| `Phi-4-mini-instruct` | Microsoft | MIT | チャット（小型） |
| `Phi-4-multimodal-instruct` | Microsoft | MIT | チャット（multimodal/LoRA） |
| `multilingual-e5-large` | 学術 | MIT | embeddings |
| `whisper-large-v3-turbo` | OpenAI | MIT | 音声文字起こし |
| `plamo-2.0-31b` | Preferred Networks | 個別契約 | チャット（クローズド） |
| `cotomi3` | NEC | 個別契約 | チャット（クローズド） |
| `Kimi-K2.5` | Moonshot AI | Modified MIT | チャット |

> **補足（種別欄）**: 「種別」は API model 文字列・モデル名・公開情報からの**推測**であり、ライセンス表ページ（S6）にはカテゴリ分類の明示記載はない。reasoning / MoE / vision 等のラベリング自体が公式マニュアル上にされていない（**公式記載なし**）。

### 2.2 操作ガイド（S5）に記載のモデル（提供チャネル別）

S5 では用途別に区分されている：

- **チャットモデル**: `Qwen3-Coder-30B-A3B-Instruct` / `Qwen3-Coder-480B-A35B-Instruct-FP8` / `gpt-oss-120b` / `llm-jp-3.1-8x13b-instruct4`
- **埋め込みモデル**: `multilingual-e5-large`, **`preview/Qwen3-Embedding-4B-FP16`**
- **音声文字起こし**: `whisper-large-v3-turbo`
- **音声合成**: VOICEVOX 各話者（ずんだもん 他）

### 2.3 GA / preview の区分

- **公式マニュアル全体で「preview/」プレフィックスが付いているのは S5 の埋め込みモデル `preview/Qwen3-Embedding-4B-FP16` の 1 件のみ**（要再検証）。
- ライセンス表ページ（S6）では `Qwen3-VL-30B-A3B-Instruct` 等は preview/ プレフィックス無しで掲載されているが、**S6 の表記が API での実際の `model` 文字列と一致するかは公式に明示されていない**。
- preview モデルの SLA、提供終了リスク、互換性に関する免責に**該当する公式記載は見つからなかった**（S5・S6 ともに記載なし）。
- **要実機検証**: S6 と S5 で表記揺れがある。実 API での `GET /v1/models` 相当（OpenAPI 上には未定義）または実リクエストでの 404 / 200 検証が必要。

### 2.4 クローズドモデル（PLaMo / cotomi 等）の取扱い（出典: S8）

- 申請方式:
  - 「利用可能なモデル」一覧から申請ボタン → フォーム送信
  - **法人アカウントのみ** 対応
  - モデル提供元による事前審査（**原則 7 営業日前後**）
- 料金:
  - **無償枠の対象外**（S8 原文）
  - 利用量に応じて料金発生
- 制限:
  - 利用用途によっては不許可
  - 審査基準・不許可理由は個別回答不可
- 個人検証は不可能。**本プロジェクトのスコープ外**。

### 2.5 GA 提供開始

- 公式ニュースリリース（S13）: 2025-09-24 に一般提供開始

---

## 3. 公式が明示している対応機能（OpenAPI 仕様 S10 ベース）

> 以下は **OpenAPI 仕様（S10）に明記されているもの** のみを列挙する。Redoc バンドル経由で取得した一次情報。

### 3.1 chat completions（POST /v1/chat/completions）

OpenAPI requestBody schema に**明示的に列挙されているプロパティ**は以下のみ:

| パラメータ | 型 | 既定値 | 制約 | 公式説明 |
|---|---|---|---|---|
| `model` | string | — | required | 利用するチャットモデル名 |
| `messages` | array | — | required | チャットのメッセージ履歴 |
| `max_tokens` | integer | — | minimum: 1 | 応答生成に使用する最大トークン数 |
| `temperature` | number | 1 | 0〜2 | 多様性制御 |
| `tool_choice` | (object\|enum) | — | — | モデルのツール利用方針を制御 |
| `tools` | array | — | — | モデルが利用可能なツールのリスト |
| `stream` | boolean | false | — | ストリーミング応答を有効にするか |

仕様冒頭に明記されている**一般注意**（S10 原文）:

> 「チャット補完のリクエストの代表例です。利用するモデルによってはサポートされていないパラメータもありますので、ご注意ください。」

> 「チャットのメッセージ履歴。モデルによってサポートしているメッセージタイプが異なります。」

#### messages（role）の対応

OpenAPI schema 上で許容されている role:

- `developer`（developer message, content required）
- `system`（system message, content required）
- `user`（user message, content required）
- `assistant`（assistant message, content optional）
- `tool`（tool message, content + tool_call_id required）

#### user message の content

- `string` または `array` を許容
- array の要素として `text` パートおよび **`image_url` パート** を許容
  - `image_url.url` は **「MIMEタイプ情報を付与した base64 エンコードされた画像データ」** に限定（例: `data:image/png;base64,xxx...`）
  - **OpenAI 互換でよくある外部 URL 直指定の挙動には言及なし**

#### assistant / system / developer / tool message の content

- 配列形式は **text パートのみ**（image は assistant 等で送り返せない）

### 3.2 streaming

- `stream: true` 対応（OpenAPI 上で boolean プロパティとして定義、既定 false）。
- 応答形式（SSE フォーマット、`data:` プレフィックス、`[DONE]` 等）の**詳細は OpenAPI に未記載**。
- 公式 Zenn（Z1）に Postman での生応答例あり:
  ```
  data: {"id":"chatcmpl-...","choices":[{"delta":{"content":"こんにちは"}}]}
  ```
  → OpenAI 互換の SSE 形式に従っているとみられる（**ただし公式マニュアル本体での明文化は無し**）。

### 3.3 function calling / tools

- **OpenAPI 上に明示的に定義されている**（S10）。これは公式マニュアル本文（S2〜S5）には書かれていない、**API 仕様にしか書かれていない**情報である点に注意。
- 定義内容:
  - `tools`: `[{ type: "function", function: FunctionObject }]` の配列
  - `FunctionObject`: `{ name (required), description, parameters }`
    - `name` 制約: 「英数字、アンダースコア、ハイフンのみ使用可能で、最大64文字まで」
    - `parameters` は `type: object`（JSON Schema 想定だが**型は object として宣言のみ**）
  - `tool_choice`: `none` / `auto` / `required` / `{ type: "function", function: { name } }`
- tool message を返す際の構造（`role: "tool"`, `tool_call_id`, `content`）も定義済み。
- **重要**: Playground（S4）には次の明示記載がある:
  > 「Playground では Function Call などの機能は利用できません。簡易的なチャット補完の動作確認用としてご利用ください」

  → **API としては受理されるが Playground では試せない**。

### 3.4 構造化出力（response_format / json_schema）

- **OpenAPI 仕様（S10）に `response_format` パラメータの定義は存在しない**。
- 公式マニュアル本文（S2〜S5）にも**「構造化出力」「json_schema」「response_format」の文字列は確認できない**。
- 検索（WebSearch）でも公式記述はヒットせず、公式 Zenn 記事（Z1〜Z4）のいずれも構造化出力に触れていない。
- **結論**: **公式は構造化出力をサポート機能として明示していない**。送付すれば「不明なフィールド」として無視されるか、モデル/推論エンジンの実装次第で何らかの効果が出る可能性はあるが、**いずれにせよ要実機検証**。

### 3.5 vision（image input）

- chat completions の user message content に `image_url` パートが OpenAPI 上で**明示的に定義されている**（S10）。
- ただし:
  - URL 形式は **base64 data URI に限定**（外部 HTTPS URL を渡せるかは公式に明示なし）
  - **どのモデルが image_url を解釈するかは仕様上明示されていない**（`Qwen3-VL-30B-A3B-Instruct`, `Phi-4-multimodal-instruct` が候補だが、対応マッピング表は無い）
  - assistant 側からの画像出力は不可（content part は text のみ）

### 3.6 embeddings

- **POST /v1/embeddings**（OpenAPI S10 で定義）
- requestBody:
  - `model` (required, string)
  - `input` (required, string または string 配列)
- レスポンス: `{ model, data: [{ index, object, embedding: [...] }] }`
- 提供モデル: `multilingual-e5-large`, `preview/Qwen3-Embedding-4B-FP16`（S5）, `Qwen3-Embedding-4B`（S6）
- **`encoding_format`, `dimensions`, `user` 等のパラメータは OpenAPI に未定義**。

### 3.7 audio (transcriptions)

- **POST /v1/audio/transcriptions**（multipart/form-data）
- パラメータ: `file` (required), `model` (`whisper-large-v3-turbo` のみ enum 指定), `language` (default `ja`), `prompt`, `temperature` (0〜1, default 0), `stream`
- 制限（S5）: 「30 分または 30MB の制限あり」

### 3.8 audio (TTS)

- **POST /v1/audio/speech**（OpenAI 互換）
- 制限・挙動（S10 の description, examples 原文ママ）:
  - 「instructions は指定できますが現在は無視されます」
  - 「response_format は指定できますが現在は常に wav を返します」
  - 「stream は非対応です（stream_format を指定してもストリーミングにはなりません）」
- 別途 VOICEVOX 互換エンドポイントあり: `POST /tts/v1/audio_query`, `POST /tts/v1/synthesis`

### 3.9 「OpenAI 互換」と謳っている範囲（出典: S12, S13）

- 公式サービスサイト（S12）原文:
  > 「OpenAI 互換 API で最新の LLM が使え」「業界標準の OpenAI API と互換性」
- ニュースリリース（S13）抜粋:
  > 「The API is compatible with the industry standard OpenAI API, so users already using OpenAI API can migrate smoothly.」
- **どの機能までが「互換」の範囲かは公式には定義されていない**。OpenAPI（S10）で明示されているのは §3.1〜3.8 の範囲のみ。

---

## 4. 制限事項

### 4.1 料金プラン（出典: S12, S13）

| プラン | 内容 |
|---|---|
| 基盤モデル無償プラン | 無償枠内利用が無料、超過時は**レート制御**がかかる。**申し込み数に上限あり**（達した場合は受付停止） |
| 従量課金プラン | 無償枠超過分は**各基盤モデルの最小単位（10,000 トークン／60 秒）ごとに料金** |

### 4.2 無償枠（両プラン共通、出典: S12, S13）

| サービス | 月間無償枠 |
|---|---|
| Chat completions | **3,000 リクエスト/月** |
| Embeddings | **10,000 リクエスト/月** |
| Audio transcription (Whisper) | **50 リクエスト/月** |
| Text-to-Speech (VOICEVOX) | **50 リクエスト/月** |
| ドキュメント / RAG | **無償枠なし** |

### 4.3 従量課金料金（出典: S13、超過時単価）

| モデル | 入力 | 出力 |
|---|---|---|
| gpt-oss-120b | 0.15 円/10,000 トークン | 0.75 円/10,000 トークン |
| llm-jp-3.1-8x13b-instruct4 | 0.15 円/10,000 トークン | 0.75 円/10,000 トークン |
| Qwen3-Coder-30B | 0.15 円/10,000 トークン | 0.75 円/10,000 トークン |
| Qwen3-Coder-480B | 0.30 円/10,000 トークン | 2.50 円/10,000 トークン |
| Whisper | — | 0.50 円/60 秒 |
| Embeddings | 2 円/10,000 トークン | 無料 |
| RAG | — | 3 円/100 チャンク |

> **注**: S13 のニュースリリースは一部文字化けしていたため、上記は WebFetch の抽出結果のうち判読できた数値。**料金最新版は公式サイト（S12）で要再確認**。

### 4.4 タイムアウト

- **公式記載なし**（要実機検証）。OpenAPI のレスポンスステータスに `504` が定義されているのでサーバ側タイムアウトは存在する模様。

### 4.5 最大トークン数 / コンテキスト長

- chat completions の `max_tokens` は OpenAPI 上 `minimum: 1` のみ指定で**上限値の記載なし**。
- モデルごとのコンテキスト長は**公式に表として明示されていない**（**要実機検証**）。

### 4.6 その他の API 上の制約

- TTS:
  - input 最大 1000 文字（OpenAPI `maxLength: 1000`）
  - 音声合成 Zenn 記事系の記述（S5 や S10 description）も「1000 文字程度の制限」と一致
- Audio transcription: 30 分または 30 MB（S5）
- function tool name: 英数字・アンダースコア・ハイフンのみ、最大 64 文字（S10）

### 4.7 レート制限

- 無償プラン超過時: 「レート制御がかかる」（S12, S13）— **具体値（RPS, RPM）は公式記載なし**
- 従量課金プラン: 課金で継続、最小課金単位「10,000 トークン／60 秒」あり（S13）
- HTTP 429 が OpenAPI レスポンスに定義されている（S10）

### 4.8 データ取扱い（出典: S1, S12, S13）

- 国内データセンター完結、VPN/LGWAN 対応の閉域構成
- 「お客様のデータは LLM モデルの学習に使われない」（S1 原文）

---

## 5. 公式が「言っていない」こと（重要）

| 項目 | 公式記載状況 |
|---|---|
| `response_format` / `json_schema` 等の構造化出力 | **公式マニュアル本文・OpenAPI 仕様ともに記載なし**。サポートの明示も非サポートの明示もない |
| function calling のサポート明示 | **マニュアル本文（操作ガイド・基本情報）に記載なし**。API 仕様（OpenAPI S10）には定義あり、ただし「モデルによっては対応しない」旨の一般注記のみ |
| `tool_choice` の各モデルでの実挙動 | 仕様に列挙はあるが**モデル別対応表なし** |
| Playground での tools サポート | **明示的に「利用できません」**と記載（S4） |
| モデル別の機能対応マトリクス（vision / tools / reasoning） | **公式に存在しない**（S5 のチャットモデル一覧は機能差異への言及なし） |
| preview モデルの SLA / 提供終了通知方針 | **記載なし** |
| preview モデルの提供終了リスクに対する免責 | **記載なし** |
| reasoning モデル（gpt-oss-120b 等）の `reasoning_content` 出力フィールド仕様 | **OpenAPI に未定義**、応答スキーマも `200: Success` のみで詳細記述なし |
| 各モデルの最大コンテキスト長 | **記載なし** |
| 各モデルの最大 `max_tokens` 上限 | **記載なし** |
| 既定タイムアウト値 | **記載なし** |
| レート制限の具体値（RPS, RPM, TPM） | **記載なし**（「レート制御がかかる」の文言のみ） |
| `seed`, `top_p`, `n`, `stop`, `presence_penalty`, `frequency_penalty`, `logprobs`, `logit_bias`, `user` 等の OpenAI 互換パラメータ | **OpenAPI に未定義**。受理されるかは未明示（**要実機検証**） |
| `image_url` で外部 HTTPS URL を渡せるか | **OpenAPI は `data:image/...;base64,...` 形式のみ記述**。外部 URL は未明示 |
| `GET /v1/models` 相当のモデル一覧取得 API | OpenAPI に**定義なし**（コントロールパネル参照を促す記述のみ） |
| credentials の Rails 規約上の推奨配置 | **記載なし** |
| Ruby / RubyLLM 向けの公式サンプル | **記載なし**（Z2/Z3 は Python・OpenAI SDK / Strands / DSPy のみ） |

---

## 6. 公式・公式 Zenn から得られる利用例

### 6.1 Strands Agents（Python, 出典: Z2）

```python
from strands import Agent
from strands.models.openai import OpenAIModel

model_openai = OpenAIModel(
    client_args={
        "api_key": "YOUR_API_KEY",
        "base_url": "https://api.ai.sakura.ad.jp/v1",
    },
    model_id="gpt-oss-120b",
    params={"max_tokens": 1000, "temperature": 0.7}
)
agent_openai = Agent(model=model_openai)
response = agent_openai("質問文")
```

- **OpenAI SDK 互換クライアントで `base_url` を差し替えるパターン**を公式が紹介している。
- function calling やストリーミング、構造化出力には**この記事では触れられていない**（次回記事に持ち越し旨）。

### 6.2 DSPy（Python, 出典: Z3）

- LM 設定: `model="openai/gpt-oss-120b"`, `api_base="https://api.ai.sakura.ad.jp/v1"`
- 実装は `dspy.ChainOfThought("question -> answer")` ＋ `BootstrapFewShot`
- **function calling / 構造化出力への言及なし**

### 6.3 ストリーミング（Postman, 出典: Z1）

- `stream: true` で SSE 応答（`data: {...}` 行が複数）
- パース処理を JS で行うサンプル

### 6.4 コーディングエージェント（参考、Z6）

- `qwen-code` から `OPENAI_BASE_URL=https://api.ai.sakura.ad.jp/v1`, `OPENAI_MODEL=Qwen3-Coder-480B-A35B-Instruct-FP8` で利用
- **公式記事ではないため一次情報としての扱いに注意**

### 6.5 ベストプラクティス的な記述

- 公式 Zenn・公式マニュアルともに、「ベストプラクティス」「推奨設定」を体系立てて示すドキュメントは**確認できなかった**。
- Z2 記事は「base_url 差し替えで OpenAI SDK 流用」という最小パターンの実例。

---

## 7. RubyLLM 連携の観点での要点（一次情報の境界）

OpenAI 互換境界を RubyLLM v1.x の主要機能と突合する:

| RubyLLM 機能 | 関連 OpenAI パラメータ | Sakura 公式が明示しているか |
|---|---|---|
| 接続（base URL 差し替え） | — | ✅ `https://api.ai.sakura.ad.jp` 明示 |
| 認証 | Bearer | ✅ |
| `chat` 基本（messages, model） | `messages`, `model` | ✅ |
| `temperature` | `temperature` | ✅（0〜2, 既定 1） |
| `max_tokens` | `max_tokens` | ✅（minimum 1、上限なし） |
| `stream` | `stream` | ✅（boolean のみ。SSE 詳細は未記載） |
| `with_tool` / Function Calling | `tools`, `tool_choice` | △ **OpenAPI には定義あり**、本文マニュアルには記述なし、Playground 非対応 |
| `with_schema` / Structured Output | `response_format`, `json_schema` | ❌ **公式に一切の記載なし** |
| Vision（`with: image`） | content `image_url` | △ OpenAPI に定義あり、ただし **base64 data URI 限定**、対応モデルは公式マッピングなし |
| `seed` / 再現性 | `seed` | ❌ **OpenAPI に未定義** |
| `top_p`, `n`, `stop`, `presence_penalty` 等 | 同左 | ❌ **OpenAPI に未定義** |
| Embeddings | `/v1/embeddings` | ✅（`input` と `model` のみ。`dimensions` 等は未定義） |
| エラーハンドリング | HTTP 400/401/429/500/504 | ✅ ステータスのみ。エラーボディスキーマは未定義 |
| `RubyLLM::Models` registry での model 解決 | — | ❌ `GET /v1/models` 相当の API は OpenAPI 未定義（registry 連携は assume_model_exists 系の対応が必要と推察） |

---

## 8. 次工程（実機検証）への引き継ぎ事項

公式情報「だけ」ではこれ以上確定できない論点。実機で検証すべきもの。

1. **`response_format` / `json_schema` の API 受理状況**（公式記載なし → 実機で送付して 200/400 を確認）
2. **`tools` を送ったときのモデル別実挙動**（特に `Phi-4-mini` 等小型モデル、`gpt-oss-120b` の reasoning 出力との競合）
3. **`image_url` に外部 HTTPS URL を渡したときの挙動**（OpenAPI は base64 data URI 限定の記述）
4. **GA / preview の API 上の正しい model 文字列**（S5 と S6 の表記揺れの確定。`/v1/models` 相当 API は無いため、リクエスト試行で 200/404 を確認）
5. **モデル別の最大コンテキスト長 / `max_tokens` 上限**
6. **`seed`, `top_p`, `n` 等 OpenAPI 未定義パラメータの受理／無視／エラーの挙動**
7. **タイムアウト既定値・延長の可否**
8. **レート制限の具体値（RPS, RPM）と 429 時の Retry-After ヘッダの有無**
9. **エラーレスポンスの JSON ボディ構造**（OpenAI 形式 `{ error: { message, type, code } }` か否か）
10. **reasoning モデル（gpt-oss-120b）の応答に `reasoning_content` 等の追加フィールドが含まれるか**
11. **SSE のフォーマット詳細**（`[DONE]` ターミネータ、`finish_reason` 等）

---

## 9. 補足：未取得・取得失敗の URL

| URL | 状況 | 原因 |
|---|---|---|
| `https://manual.sakura.ad.jp/api/cloud/ai-engine/inference.html` | HTML 取得は成功するが本文空 | クライアントレンダリング（Redoc）。OpenAPI YAML（S10）から実体取得済み |
| `https://manual.sakura.ad.jp/api/cloud/ai-engine/rag.html` | 同上 | 同上（S11 から取得済み、本調査ではスコープ外） |
| `https://www.sakura.ad.jp/corporate/information/newsreleases/2025/09/24/1968221046/` | 取得は成功したが**一部本文文字化け** | エンコーディング問題。料金表は他経路（S12）で補完済 |
| `https://zenn.dev/sakura_internet/articles/ai-engine-kijiyomu` のコード詳細 | 本文の概要のみ取得、サンプルコードは GitHub 参照と記載されており取得せず | 必要に応じて `github.com/tokuhirom/kijiyomu` を別途確認 |

---

## 10. 重要な注記

- 本ドキュメントは **2026-05-09 時点** の一次情報のスナップショット。公式マニュアル・OpenAPI 仕様は予告なく変更される。
- OpenAPI 仕様（S10）に記載の項目は「**API として定義されている**」ことを示すが、それが「**全モデルで動作する**」ことは意味しない。仕様冒頭にも「利用するモデルによってはサポートされていないパラメータもあります」と明記されている。
- 「公式が言っていない」項目を「公式は対応していない」と読み替えてはならない。実機検証なしには判断できない。
- preview モデルは公式に SLA・終了通知方針が明記されていないため、本番依存は技術的リスクが大きい（**この点は公式記載がないこと自体がリスクの根拠**）。
