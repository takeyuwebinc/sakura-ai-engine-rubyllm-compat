# さくらのAI Engine OpenAI API 互換性 — Sakura 公式 OpenAPI 仕様基準の比較調査

**作成日**: 2026/05/09
**ステータス**: Final
**最終確認日**: 2026-05-10
**対象 API**: Sakura `https://api.ai.sakura.ad.jp/v1` / 公式 OpenAI `https://api.openai.com/v1`
**検証ツール**: `bin/probe`, `bin/compare`（本リポジトリ）
**検証 Ruby**: 4.0.2 / `ruby_llm` 1.15.0

---

## 概要

### 調査の背景

さくらインターネット「さくらのAI Engine」は OpenAI API 互換を謳うが、互換の境界は公式に定義されていない。サービスサイト（[公式サイト](https://www.sakura.ad.jp/aipf/ai-engine/)）に「OpenAI 互換 API」という表現はあるが、どのパラメータ／挙動が公式 OpenAI と一致するかは記述されていない（GA を伝える [2025-09-24 ニュースリリース](https://www.sakura.ad.jp/corporate/information/newsreleases/2025/09/24/1968221046/)本文にも互換範囲の定義はなく、「REST API として提供」とだけ記される）。

本調査は **Sakura 公式 OpenAPI 仕様（[ai-engine-inference-api.json](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json)）に明示されている範囲のみ**を対象に、公式 OpenAI API の実機挙動と差分を確認する。

### 調査の目的

- Sakura 公式 OpenAPI に明示された機能（接続・モデル・tools・streaming・vision・基本パラメータ・エラー応答）が、公式 OpenAI API と同じように振る舞うかを判定する
- 「OpenAI 互換」という表現の実体的な範囲を、公式仕様基準で特定する
- 互換性ギャップが存在する場合、どのレイヤ（HTTP コード／エラーボディ構造／応答フィールド）に発生するかを切り分ける

### 調査範囲

#### 対象（Sakura OpenAPI 明示プロパティ）

`POST /v1/chat/completions` の requestBody schema に明記された 7 プロパティ:

| プロパティ | OpenAPI 制約 |
|---|---|
| `model` | required, string |
| `messages` | required, role: developer / system / user / assistant / tool |
| `max_tokens` | minimum: 1 |
| `temperature` | 0〜2, default 1 |
| `tool_choice` | none / auto / required / named |
| `tools` | function 配列 |
| `stream` | boolean, default false |

加えて以下のレスポンス／エンドポイント挙動:

- HTTP ステータス: 200 / 400 / 401 / 429 / 500 / 504（OpenAPI 定義済み）
- Vision: user message content の `image_url` パート（base64 data URI 限定の記述）
- Streaming: `stream: true` の SSE 応答

#### スコープ外

- Sakura OpenAPI 未定義のパラメータ全般（`response_format` / `seed` / `top_p` / `n` / `stop` / `presence_penalty` / `frequency_penalty` / `logprobs` / `user` ほか）。これらは「未対応」として深掘りしない。
- `embeddings`, `audio/transcriptions`, `audio/speech`, TTS の `tts/v1/*`（OpenAI 互換境界の主軸である chat completions に絞る）
- レート制限の具体値（無償枠／従量課金境界）の詳細測定
- モデル別の能力差（reasoning content の意味的差異など）

---

## 調査内容

### 調査対象

- **Sakura AI Engine** チャットモデル代表: `gpt-oss-120b`（GA、`bin/probe` 既定）
- **Sakura AI Engine** Vision モデル代表: `preview/Qwen3-VL-30B-A3B-Instruct`
- **公式 OpenAI** 比較モデル: `gpt-4o-mini`（テキスト + vision 両対応で安価、`bin/probe --provider openai` 既定）

### 調査方法

`bin/probe`（[lib/probes/](../../lib/probes/) 配下のスクリプト）を Sakura / OpenAI 双方に対して実行し、生 HTTP レスポンスと RubyLLM 経由の挙動を [tmp/probe_results/<provider>__<probe>__<model>.json](../../tmp/probe_results/) に保存。同じ probe 名のファイルを `bin/compare` でシナリオ単位に並べ、HTTP ステータス・ボディキー構造・finish_reason を表形式で diff した。

実行した probe（Sakura OpenAPI のスコープ内のみ）:

| probe | 対象機能 | 検証点 |
|---|---|---|
| [a_connect](../../lib/probes/a_connect.rb) | 接続・認証・基本 chat | 200 取得、role 受理、応答ボディ構造 |
| [b_models](../../lib/probes/b_models.rb) | `GET /v1/models`（注: Sakura OpenAPI に未定義のエンドポイント） | モデル ID 受理性 |
| [d_tools](../../lib/probes/d_tools.rb) | tools / tool_choice の各モード | `tool_calls` 取得、`finish_reason: tool_calls` |
| [e_streaming](../../lib/probes/e_streaming.rb) | `stream: true` の SSE | chunk 数、`usage` chunk の有無 |
| [f_vision](../../lib/probes/f_vision.rb) | `image_url`（base64 / 外部 HTTPS URL） | 画像入力の受理性 |
| [g_errors](../../lib/probes/g_errors.rb) | 認証エラー・モデル不正・OpenAPI 制約違反 | HTTP コード、エラーボディ構造、RubyLLM 例外マッピング |

スコープ外として実行を見送った probe:

- [c_schema](../../lib/probes/c_schema.rb): `response_format` / `json_schema` を扱う。Sakura OpenAPI に未定義のため本調査スコープ外。
- [h_params](../../lib/probes/h_params.rb): `seed` / `top_p` / `n` / `stop` 等を扱う。同上。

#### 検証環境

| 項目 | 値 |
|---|---|
| 検証日 | 2026-05-09 〜 2026-05-10 |
| Ruby | 4.0.2 (`bundle exec ruby --version` で確認) |
| `ruby_llm` | 1.15.0 |
| Sakura 検証モデル | `gpt-oss-120b`（chat）/ `preview/Qwen3-VL-30B-A3B-Instruct`（vision） |
| OpenAI 検証モデル | `gpt-4o-mini` |

#### 検証時の制約

- 公式 OpenAI 側で初回測定時 (2026-05-09) に複数シナリオが HTTP 429（rate limit）を返したが、翌日 (2026-05-10) の再測定で全シナリオの応答が取得できた。最終結果は再測定後のデータを使用している。
- 検証は単発リクエストベースで実施。同時並行リクエストやレート制限到達時の挙動は本調査の対象外。

---

## 調査結果

> 各結果のソース: `tmp/probe_results/<provider>__<probe>__<model>.json`。`bin/compare <probe>` で再現可能。Sakura 公式 OpenAPI の引用は [ai-engine-inference-api.json](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json) より。

### 1. 接続・認証・基本 chat（probe: a_connect）

| 検証項目 | Sakura | 公式 OpenAI | 一致 |
|---|---|---|---|
| 最小 chat completion (`raw_minimal`) | HTTP 200 | HTTP 200 | ✅ |
| `system` role を含む chat (`raw_with_system`) | HTTP 200 | HTTP 200 | ✅ |
| `developer` role を含む chat (`raw_with_developer`) | HTTP 200 | HTTP 200 | ✅ |
| RubyLLM 経由の基本 chat | OK | OK | ✅ |
| RubyLLM `openai_use_system_role: false` | OK | OK | ✅ |

ソース: `tmp/probe_results/sakura__a_connect__gpt-oss-120b.json`、`tmp/probe_results/openai__a_connect__gpt-4o-mini.json`。

#### 1.1 応答ボディの構造差（OpenAPI に応答スキーマ定義がないため事実記録のみ）

Sakura OpenAPI（[ai-engine-inference-api.json](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json)）の `responses.200` は `description: Success` のみで、レスポンスのプロパティ定義は存在しない。実機の差分を以下に記録する（自己検証）。

| 階層 | Sakura `gpt-oss-120b` のキー | 公式 OpenAI `gpt-4o-mini` のキー |
|---|---|---|
| top-level | `id`, `object`, `created`, `model`, `choices`, `service_tier`, `system_fingerprint`, `usage`, **`prompt_logprobs`**, **`prompt_token_ids`**, **`kv_transfer_params`** | `id`, `object`, `created`, `model`, `choices`, `usage`, `service_tier`, `system_fingerprint` |
| `message` | `role`, `content`, `refusal`, `annotations`, `audio`, **`function_call`**, **`tool_calls`**, **`reasoning_content`** | `role`, `content`, `refusal`, `annotations` |

太字は公式 OpenAI の chat completion 応答に存在しない／非推奨のフィールド。`function_call` は OpenAI 公式リファレンスで [deprecated と明記](https://developers.openai.com/api/reference/python/resources/chat/subresources/completions) されている旧フィールドで、`tool_calls` への移行が指示されている。`reasoning_content` は本実機で `gpt-oss-120b` の応答に含まれるフィールドだが、[vLLM 公式ドキュメント](https://docs.vllm.ai/en/latest/features/reasoning_outputs/)では同種のフィールドは `reasoning` にリネームされており、Sakura 側で動作する vLLM のバージョン／実装差で名称が異なっていると見られる（バージョン特定は本調査の対象外）。`prompt_logprobs` / `prompt_token_ids` / `kv_transfer_params` は名称・性質ともに vLLM 系の拡張フィールドと一致しており（[vLLM の chat completion 拡張](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html) で類似フィールドが定義されている）、Sakura が vLLM 系の推論サーバを採用していると推測される。

### 2. モデル一覧（probe: b_models）

> Sakura 公式 OpenAPI（[ai-engine-inference-api.json](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json)）には **`GET /v1/models` エンドポイントは定義されていない**。本節は「OpenAPI 未定義だが OpenAI 互換の標準エンドポイントとして実機がどう振る舞うか」を事実として記載する。

| 検証 | Sakura 実機 |
|---|---|
| `GET /v1/models` | HTTP 200、`{ "object": "list", "data": [...] }` を返す（OpenAI 互換形式） |
| 不明モデル ID で chat 実行 | HTTP 400 `{"error":{"message":"This model is not available."}}` |

ソース: `tmp/probe_results/sakura__b_models__all.json`。

公式 OpenAI は `GET /v1/models` を OpenAPI 上に定義しているため、エンドポイントの存在自体は両者一致。Sakura 側は OpenAPI 上は未定義だが実装は存在する（仕様書に意図的に載せていないのか、定義漏れなのかは外部からは判断できない）。

### 3. tools / tool_choice（probe: d_tools）

| シナリオ | Sakura `gpt-oss-120b` | 公式 OpenAI `gpt-4o-mini` | 互換性 |
|---|---|---|---|
| `tool_choice: auto` (`raw_tools_auto`) | HTTP 200, `has_tool_calls: true`, `finish_reason: tool_calls` | HTTP 200, `has_tool_calls: true`, `finish_reason: tool_calls` | ✅ 一致 |
| `tool_choice: required` | HTTP 200, `has_tool_calls: true`, `finish_reason: tool_calls` | HTTP 200, `has_tool_calls: true`, `finish_reason: tool_calls` | ✅ 一致 |
| `tool_choice: { type: "function", function: { name } }` | HTTP 200, `has_tool_calls: true`, `finish_reason: tool_calls` | HTTP 200, `has_tool_calls: true`, **`finish_reason: stop`** | ⚠️ `finish_reason` 差 |
| `tool_choice: none` | HTTP 200, **`has_tool_calls: true`**, `finish_reason: tool_calls` | HTTP 200, `has_tool_calls: false`, `finish_reason: stop` | ❌ 非互換 |
| tool 不要なプロンプト + tools 配列 | HTTP 200, `has_tool_calls: false`, `finish_reason: stop` | HTTP 200, `has_tool_calls: false`, `finish_reason: stop` | ✅ 一致 |
| RubyLLM `with_tool` で multi-turn | OK | OK | ✅ 一致 |

ソース: `tmp/probe_results/sakura__d_tools__gpt-oss-120b.json`、`tmp/probe_results/openai__d_tools__gpt-4o-mini.json`。

#### 3.1 `tool_choice: none` の非互換（確定）

Sakura 公式 OpenAPI（[ai-engine-inference-api.json](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json) の `ChatCompletionToolChoiceOption`）は `none` を含む 4 値を enum として定義しているが、`gpt-oss-120b` では `none` を指定しても **`tool_calls` が返り `finish_reason: tool_calls` となる**（本来 `none` はモデルにツール呼び出しを抑制させ、通常の自然文応答を返させる指定）。同条件で公式 OpenAI `gpt-4o-mini` は `has_tool_calls: false`、`finish_reason: stop` を返し、自然文（"東京の現在の天気を取得します。少々お待ちください。"）で応答する。Sakura 側で `none` 指定が無視されていることが確定した。

#### 3.2 `tool_choice: named` の `finish_reason` 差

両者とも `tool_calls` 配列に指定された関数の呼び出しを含むが、`finish_reason` の値が異なる（Sakura: `tool_calls` / OpenAI: `stop`）。`tool_calls` の中身（関数名・引数）は両者で一致しており、ツール呼び出し自体の互換性に実害はない。`finish_reason` で会話終端を判定するクライアントは Sakura 側で `tool_calls` を見る点に注意。

### 4. streaming（probe: e_streaming）

| シナリオ | Sakura | 公式 OpenAI | 差分 |
|---|---|---|---|
| `stream: true`、`stream_options.include_usage` 無し | HTTP 200, **usage chunk が含まれる** (`usage_chunk_seen: true`), 85 chunks | HTTP 200, **usage chunk なし**, 10 chunks | ⚠️ usage chunk の既定挙動が異なる |
| `stream: true`、`stream_options.include_usage: true` | HTTP 200, usage chunk あり, 78 chunks | HTTP 200, usage chunk あり, 11 chunks | ✅ 一致 |
| `finish_reason` | `stop` | `stop` | ✅ 一致 |
| RubyLLM streaming | OK | OK | ✅ 一致 |
ソース: `tmp/probe_results/sakura__e_streaming__gpt-oss-120b.json`、`tmp/probe_results/openai__e_streaming__gpt-4o-mini.json`。

> 注: `RubyLLM streaming + with_schema` シナリオは `response_format` 経路を伴うため本調査スコープ外（probe 結果ファイルには含まれるが本表から除外）。

chunk 数の差はトークンあたりの chunk 細分化の差や応答テキスト長の差など複合要因が考えられるため、本調査では互換性判定の指標としない（chunk 数自体の比較は OpenAPI スコープ外）。

### 5. vision（probe: f_vision）

Sakura 公式 OpenAPI（[ai-engine-inference-api.json](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json) の `ChatCompletionRequestMessageContentPartImage`）は `image_url.url` を **「MIME タイプ情報を付与した base64 エンコードされた画像データ」** と記述しており、外部 HTTPS URL の取扱いには言及がない。

| シナリオ | Sakura `preview/Qwen3-VL-30B-A3B-Instruct` | 公式 OpenAI `gpt-4o-mini` | 互換性 |
|---|---|---|---|
| 外部 HTTPS URL を `image_url.url` に指定 | HTTP 200。応答: "Pythonのロゴです。" | HTTP 200。応答: "Pythonのロゴが描かれています。" | ✅ 受理性は一致 |
| base64 data URI を指定 | HTTP 200。応答: "Debianのロゴです。" | HTTP 200。応答: "画像には、渦巻き模様のデザインが描かれています。"（画像内容の認識精度はモデル差） | ✅ 受理性は一致 |
| RubyLLM `chat.ask(..., with: image_path)` | OK | OK | ✅ 一致 |

ソース: `tmp/probe_results/sakura__f_vision__preview_Qwen3-VL-30B-A3B-Instruct.json`、`tmp/probe_results/openai__f_vision__gpt-4o-mini.json`。

公式 OpenAI 側でも外部 HTTPS URL と base64 data URI の双方が 200 で受理される（[公式 vision ガイド](https://developers.openai.com/api/docs/guides/images-vision) でも「fully qualified URL / Base64-encoded data URL / file ID」の 3 方式を許容）。Sakura 側の実機挙動は OpenAI と同じく両方を受理しており、**API 受理性のレベルでは互換**。ただし Sakura OpenAPI 仕様の文言は base64 限定と読める記述で、実機挙動より仕様書が狭く書かれている形になる（Sakura OpenAPI を契約として読むと外部 URL 経路を実装しない判断になる可能性）。

なお、画像内容の認識精度（48×48 PNG の Debian ロゴが「渦巻き模様」と認識されるか「Debian のロゴ」と認識されるか）はモデル能力差であり、API 互換性とは独立。

### 6. エラーハンドリング（probe: g_errors）

> Sakura OpenAPI（[ai-engine-inference-api.json](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json) の `responses`）は `200 / 400 / 401 / 429 / 500 / 504` のステータスを定義するが、エラーレスポンスの JSON ボディ構造は定義していない。

| シナリオ | Sakura HTTP | 公式 OpenAI HTTP | OpenAPI 制約 | 一致 |
|---|---|---|---|---|
| `Authorization` ヘッダ無し | 401 | 401 | — | ✅ |
| `Authorization: Bearer invalid-token` | 401 | 401 | — | ✅ |
| 不明モデル ID | **400** | **404** | OpenAPI に該当ステータスは 400/401/429/500/504 のみ定義 | ❌ |
| `temperature: 99.9` | **200**（受理） | **400**（拒否） | Sakura OpenAPI は `0..2` を制約として明示 | ❌ |
| `max_tokens: 10_000_000` | **200**（受理） | **400**（拒否） | Sakura OpenAPI は `minimum: 1` のみ、上限未明示 | ❌ |
| RubyLLM 不正トークン | `RubyLLM::UnauthorizedError` | `RubyLLM::UnauthorizedError` | — | ✅ |
| RubyLLM 不明モデル | `RubyLLM::BadRequestError`（HTTP 400 経由） | `RubyLLM::Error`（HTTP 404 → RubyLLM の例外マップに該当なし） | — | ❌ |

ソース: `tmp/probe_results/sakura__g_errors__gpt-oss-120b.json`、`tmp/probe_results/openai__g_errors__gpt-4o-mini.json`。

#### 6.1 エラーレスポンスボディ構造の差

| 項目 | Sakura | 公式 OpenAI |
|---|---|---|
| 401 (Unauthorized) | `{"error":{"message":"Unauthorized"}}` | `{"error":{"message":"...","type":"invalid_request_error","param":null,"code":"invalid_api_key"}}` |
| 不明モデル | HTTP 400, `{"error":{"message":"This model is not available."}}` | HTTP 404, `{"error":{"message":"...","type":"invalid_request_error","param":null,"code":"model_not_found"}}` |
| temperature 範囲外 | HTTP 200（エラーにならず通常応答） | HTTP 400, `{"error":{"message":"...","type":"invalid_request_error","param":"temperature","code":"decimal_above_max_value"}}` |

公式 OpenAI のエラーボディは `{ error: { message, type, param, code } }` の 4 フィールド構造を一貫して持つが、Sakura は `{ error: { message } }` のみで `type` / `param` / `code` は含まれない。プログラムからエラー内容を分岐する場合、OpenAI 互換クライアントが `error.code` を見ていると Sakura 側で `nil` になる。

---

## 分析・考察

### 主要な発見

1. **基本機能（接続・認証・chat completions の最低限・streaming・tools の `auto`/`required` モード・vision の URL/base64 受理性）は OpenAI 互換**: HTTP ステータス・主要フィールドが一致し、RubyLLM など OpenAI 互換クライアントの最低限のフローは Sakura に対しても動作する。

2. **Sakura 公式 OpenAPI の数値制約は実機で強制されていない**: OpenAPI 仕様で `temperature: 0..2` と明示しているにもかかわらず `temperature: 99.9` を 200 で受理する。`max_tokens: 10_000_000` も同様に 200 で受理される。**仕様書とランタイム動作の不整合**であり、Sakura OpenAPI を契約として依存するクライアント（バリデーションを仕様から自動生成する場合など）にとっては挙動の予測が難しい。

3. **エラーハンドリングは公式 OpenAI と非互換**:
   - HTTP ステータスコードが異なる: 不明モデルは Sakura が **400**、公式 OpenAI が **404**。Sakura OpenAPI の `responses` 定義に 404 がないこと自体は内部一貫しているが、OpenAI 互換クライアントの想定とはずれる。
   - エラーボディ構造が異なる: Sakura は `{error:{message}}` のみで、公式 OpenAI が一貫して提供する `type` / `param` / `code` が無い。`error.code` で分岐するクライアントは Sakura 側で常に `nil` を見る。
   - RubyLLM の例外マッピング差は HTTP コード差の派生（404 → 汎用 `RubyLLM::Error`、400 → `RubyLLM::BadRequestError`）。

4. **`tool_choice: none` が Sakura では効かない**: 公式 OpenAI `gpt-4o-mini` は仕様通り `has_tool_calls: false`、`finish_reason: stop` で自然文応答する。Sakura `gpt-oss-120b` は `none` 指定を無視して `tool_calls` を返す。Sakura OpenAPI 仕様 (`ChatCompletionToolChoiceOption` enum) と矛盾する実装で、ツール抑制を OpenAI 互換挙動として期待するクライアントは Sakura で破綻する。

5. **`tool_choice: named` で `finish_reason` が異なる**: 両者とも tool_calls 配列に正しい関数呼び出しを含むが、Sakura は `finish_reason: tool_calls`、OpenAI は `finish_reason: stop`。`finish_reason` で会話終端を判定するクライアントは双方を考慮する必要がある。

6. **応答ボディに公式 OpenAI 仕様外のフィールドが含まれる**: top-level の `prompt_logprobs` / `prompt_token_ids` / `kv_transfer_params`、message の `function_call`（OpenAI 公式は deprecated 化）、`reasoning_content` 等。Sakura OpenAPI の `responses.200` がスキーマ定義を持たないため厳密には「仕様違反」とは言えないが、公式 OpenAI 互換クライアントが想定しないキーが含まれる。多くのクライアントは未知フィールドを無視するため実害は限定的。

7. **streaming の `usage` chunk は Sakura が既定で送信する**: 公式 OpenAI は `stream_options.include_usage: true` を明示しないと送らない。Sakura は明示しなくても送る。「OpenAI 互換」の超集合としての挙動であり、無害だが **OpenAI と同じパース処理を使うと終端後に予期しない chunk を受け取る** ため、堅牢なパーサが必要。

8. **vision の `image_url` 受理性は OpenAI と互換**: Sakura OpenAPI 文言は base64 data URI 限定の記述だが、実機では外部 HTTPS URL も 200 で受理される（公式 OpenAI と同じ挙動）。Sakura OpenAPI の記述だけを信じてクライアントを作ると外部 URL 経路を実装しない判断になる可能性がある（仕様書が実機より狭く書かれている形）。

### 技術的評価

公式 OpenAI API との互換性カテゴリを 4 段階で評価:

| カテゴリ | 評価 | 根拠 |
|---|---|---|
| HTTP プロトコル / 認証 | ✅ 完全互換 | Bearer Token, /v1/chat/completions, ステータス 200/401 が一致 |
| 基本リクエスト（model, messages, max_tokens, temperature, stream） | ✅ 受理は一致 | 主要モードが同じレスポンス構造 |
| `tool_choice: auto` / `required` | ✅ 完全互換 | 200, has_tool_calls=true, finish_reason=tool_calls が両者一致 |
| `tool_choice: named` | ⚠️ 注意 | tool_calls の中身は一致、`finish_reason` のみ Sakura=tool_calls / OpenAI=stop |
| `tool_choice: none` | ❌ 非互換 | Sakura は `none` を無視して tool_calls を返す。OpenAI は仕様通り抑制 |
| vision `image_url` 受理性（外部 URL / base64） | ✅ 互換 | 両者とも 200 で受理。Sakura OpenAPI 文言は base64 限定だが実機は外部 URL も受理 |
| streaming（基本） | ✅ 互換 | `stream: true` で SSE 応答、finish_reason 一致 |
| streaming usage chunk の既定挙動 | ⚠️ 注意 | Sakura は include_usage 無指定でも送出。OpenAI 互換パーサの想定とずれる |
| OpenAPI 制約の実機強制 | ❌ 非互換 | `temperature` 範囲外、`max_tokens` 巨大値が Sakura では 200。OpenAI は 400 |
| エラーレスポンス（HTTP ステータス・ボディ構造） | ❌ 非互換 | 不明モデルが 400 vs 404、エラーボディが `{message}` のみ vs `{message,type,param,code}` |
| 応答ボディ拡張フィールド | ⚠️ 注意 | Sakura は仕様外フィールドを追加（reasoning_content, prompt_logprobs 等）。クライアントが未知フィールドを無視できれば実害なし |

### リスクと制約

- **本番システムが Sakura OpenAPI 仕様だけを契約として実装すると、ランタイム挙動とのギャップに遭遇する**。具体的には:
  - 入力バリデーション（`temperature` の範囲、`max_tokens` の上限）を OpenAPI から自動生成しても、Sakura 側ではバリデーションを通った値以外も実機で受理される（厳密には害ではないが、制約の意味が無くなる）
  - エラーハンドリング側で OpenAI 互換の `error.code` ベース分岐を実装すると、Sakura では分岐できない
  - HTTP ステータスでハンドリングする場合、不明モデルが `404` ではなく `400` で来る点を別経路で処理する必要

- **モデルによって挙動差がある**: 本調査は `gpt-oss-120b`（Sakura）と `gpt-4o-mini`（OpenAI）の 1 対 1 比較。Sakura 側のモデルごとの差異は [既存マトリクス](compatibility-matrix.md) を参照。OpenAI 互換性の本質的差分（temperature 範囲外受理・エラーボディ構造）は推論サーバの前段（HTTP / API ゲートウェイ層）の挙動に属すると推測されるため、モデル切替によって結論が大きく変わる可能性は低いと考えるが、これは推測であり、断定には Sakura 提供モデル全種での追試が必要。

- **`tool_choice: none` と `named` の挙動差はモデル依存の可能性あり**: 本調査の Sakura 側は `gpt-oss-120b` での結果。これらは推論モデル側の tool_choice 解釈実装に起因する可能性が高く、Sakura が配備する vLLM の起動オプション（`--enable-auto-tool-choice` 等）／パーサ／モデル次第で挙動が変わり得る。`Qwen3-Coder-30B-A3B-Instruct` 等での挙動は [既存マトリクス §5.2](compatibility-matrix.md) で別途確認されているが、本報告書のスコープでは未検証。

- **時点性**: 2026-05-09 時点。Sakura 側は GA から 8 ヶ月程度。仕様書／実装の整合性は今後改善される可能性がある。

---

## 結論・推奨事項

### 結論

さくらのAI Engine は **Sakura 公式 OpenAPI で明示された範囲の「リクエストプロパティ受理性」と「成功時の HTTP/ペイロード基本構造」については OpenAI API と互換性がある**。OpenAI SDK や RubyLLM のような OpenAI 互換クライアントで base URL を差し替えるパターンは、最低限のチャット完了・streaming・tool calling（auto モード）について動作する。

ただし、以下の領域では **公式 OpenAI と挙動が異なる**:

**非互換（クライアント実装に修正が必要）**:

1. **`tool_choice: none` が無視される**（Sakura は tool_calls を返す、OpenAI は仕様通り抑制）。`gpt-oss-120b` で確定。
2. **OpenAPI 制約の実機強制が存在しない**（`temperature: 0..2`, `max_tokens: minimum 1` の境界外を 200 で受理）
3. **エラーレスポンスの HTTP ステータスとボディ構造が異なる**（不明モデル 400 vs 404、`error.code` / `error.type` / `error.param` 不在）

**注意（互換性は保たれるが想定差あり）**:

4. **`tool_choice: named` の `finish_reason` 差**（Sakura: tool_calls / OpenAI: stop。tool_calls 内容自体は一致）
5. **応答ボディに OpenAPI 未定義の追加フィールドが含まれる**（`prompt_logprobs`, `kv_transfer_params`, `reasoning_content` 等）
6. **streaming の `usage` chunk が既定で送信される**（公式 OpenAI は `stream_options.include_usage: true` 指定時のみ送信）
7. **vision の `image_url` 文言と実機の差**（Sakura OpenAPI は base64 限定の記述だが実機は外部 URL も受理。受理性は OpenAI と互換）

「OpenAI 互換」という公式表現は **「同じ OpenAI 互換クライアントで叩ける」レベルでは成立**するが、**「公式 OpenAI と振る舞いが完全に一致する」レベルでは成立しない**、という二段構えで理解する必要がある。

### 推奨事項

1. **OpenAI 互換クライアントを Sakura に向けるとき、エラーハンドリングは HTTP ステータスのみで分岐する**
   - 理由: `error.code` / `error.type` / `error.param` は Sakura 側で `nil`。クライアント側で OpenAI 互換の構造前提を残すと不明モデル時に分岐が壊れる
   - 期待効果: Sakura・OpenAI 両対応コードを単一実装で維持できる

2. **入力バリデーションは Sakura OpenAPI の制約値を信頼せず、クライアント側で独自に行う**
   - 理由: `temperature: 99.9` も `max_tokens: 10_000_000` も実機では 200。仕様書を契約とした自動生成バリデーションが意味を成さない
   - 期待効果: 想定外の値が裏側のモデルに到達して挙動不安定になるリスクを減らす

3. **応答ボディのパースは OpenAI 公式仕様にない追加フィールドを許容する設計にする**
   - 理由: `reasoning_content`, `prompt_logprobs`, `kv_transfer_params` 等が含まれる。strict-typed なパーサでは失敗する
   - 期待効果: モデル拡張・推論サーバ更新による応答形式変化に追従しやすくなる

4. **streaming パーサは usage chunk が `include_usage` 無指定でも来る前提にする**
   - 理由: 公式 OpenAI は `include_usage: true` を明示しないと usage chunk を送らないが、Sakura は既定で送る
   - 期待効果: 終端処理後に予期しない chunk が来てもエラーにならない堅牢な実装になる

5. **Vision を扱う場合、外部 HTTPS URL の利用は事実上の暗黙仕様として扱う**
   - 理由: Sakura OpenAPI 上は base64 限定の記述だが実機受理される。公式仕様外なので **将来削除される可能性**を考慮し、可能な範囲で base64 経路を併用する
   - 期待効果: Sakura 側仕様変更時の影響を抑えられる

6. **本番システムでは Sakura のモデル更新による応答フィールド／挙動変化の検知用に、本リポジトリの `bin/probe` を CI などで定期実行する**
   - 理由: 仕様書の更新が遅れる／実機挙動が変わる可能性が継続的にある
   - 期待効果: 互換性退行の早期検出

### 次のアクション

- [ ] Sakura 側の `temperature` / `max_tokens` 制約強制について、Sakura のサポートに「OpenAPI 仕様と実機の差は仕様変更予定があるか」を確認する
- [ ] エラーボディに `code` / `type` / `param` を追加する予定があるか同様に確認する
- [ ] `tool_choice: none` を仕様通り解釈させるための vLLM 設定変更／モデル別パーサ追加の可否を Sakura のサポートに確認する
- [ ] Sakura の他チャットモデル（`llm-jp-3.1-8x13b-instruct4`, `Qwen3-Coder-30B-A3B-Instruct`, `Qwen3-Coder-480B-A35B-Instruct-FP8` 等）で同 probe を実行し、本報告の結論（特に temperature/max_tokens 受理性、エラーボディ構造、`tool_choice: none` の挙動）がモデル横断で成立するか確定する

---

## 参考資料

### 一次情報

- [さくらの AI Engine Inference API 仕様（JSON）](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json)
- [さくらの AI Engine マニュアル](https://manual.sakura.ad.jp/cloud/manual-ai-engine.html)
- [さくらの AI Engine 利用手順（S3）](https://manual.sakura.ad.jp/cloud/ai-engine/02-howto.html)
- [さくらインターネット 公式サービス紹介](https://www.sakura.ad.jp/aipf/ai-engine/)
- [GA 開始ニュースリリース 2025-09-24](https://www.sakura.ad.jp/corporate/information/newsreleases/2025/09/24/1968221046/)

### 関連リポジトリ内資料

- [docs/research/01-sakura-official.md](../research/01-sakura-official.md) — Sakura 公式情報サマリ（OpenAPI 抜粋含む）
- [docs/reports/compatibility-matrix.md](compatibility-matrix.md) — RubyLLM 抽象化レイヤを含めた互換性マトリクス（本報告書はその下位層を Sakura OpenAPI スコープに絞ったもの）
- [docs/reports/troubleshooting.md](troubleshooting.md) — 落とし穴集

---

## 付録

### A. 実行コマンド一覧（再現手順）

```sh
# 双方の API キーを .env に設定後
bundle install

# Sakura 側
bundle exec bin/probe a_connect    --provider sakura
bundle exec bin/probe b_models     --provider sakura
bundle exec bin/probe d_tools      --provider sakura
bundle exec bin/probe e_streaming  --provider sakura
bundle exec bin/probe f_vision     --provider sakura
bundle exec bin/probe g_errors     --provider sakura

# 公式 OpenAI 側
bundle exec bin/probe a_connect    --provider openai
bundle exec bin/probe d_tools      --provider openai
bundle exec bin/probe e_streaming  --provider openai
bundle exec bin/probe f_vision     --provider openai
bundle exec bin/probe g_errors     --provider openai

# 差分表示
for p in a_connect d_tools e_streaming f_vision g_errors; do
  bundle exec bin/compare $p
done
```

### B. 結果ファイル

- Sakura: `tmp/probe_results/sakura__*.json`
- OpenAI: `tmp/probe_results/openai__*.json`

各ファイルは probe シナリオごとの HTTP レスポンス・RubyLLM 挙動を保持し、`recorded_at` と `ruby_llm_version` を埋め込み済み。

### C. 検証時のレート制限影響範囲（参考: 初回測定時）

初回測定 (2026-05-09) では OpenAI 側で以下のシナリオが HTTP 429（rate limit）を返したが、翌日 (2026-05-10) の再測定で全件 200 応答を取得済み。本報告書の最終結論はすべて再測定データに基づく。

| probe | 初回 429 シナリオ | 再測定後の状態 |
|---|---|---|
| d_tools | `raw_tools_required`, `raw_tools_named`, `raw_tools_none`, `raw_no_tool_needed` | 全件 200 取得済（差分は §3 に反映） |
| f_vision | `raw_external_url`, `raw_base64` | 全件 200 取得済（差分は §5 に反映） |

g_errors はシナリオ全件で初回から OpenAI 側応答取得済み。
