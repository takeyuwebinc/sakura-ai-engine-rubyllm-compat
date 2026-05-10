# RubyLLM 該当箇所読解メモ

- **対象 gem**: `ruby_llm` (https://github.com/crmne/ruby_llm)
- **確認バージョン**: `main` ブランチ commit `ff392893bb5366937688fa82bc0841185491f84c`（最新タグ `1.15.0` を含む。Bump コミットが先行 / 1.15.0 のリリース日 2026-05-07）
- **比較対象**: `1.14.1` タグ（2026-04-02）。差分は §0 に簡潔に記載
- **付随 gem**: `ruby_llm-schema` (https://github.com/danielfriis/ruby_llm-schema) `main` ブランチ
- **最終確認日**: 2026-05-09
- **読み方の前提**: ファイルパスは gem ルートからの相対。行番号は上記 main commit の値

---

## 0. v1.14 系との実質差分（OpenAI 互換用途で気にすべき点）

`configuration.rb`、`providers/openai.rb`、`providers/openai/tools.rb` は v1.14.1 と main で実質変化なし。Sakura 互換性に直接効く差分は以下のみ:

- `lib/ruby_llm/providers/openai/chat.rb` の usage パース処理が main で大幅に整理された（`input_tokens` / `output_tokens` / `cache_read_tokens` / `cache_write_tokens` / `thinking_tokens` のヘルパー化）。Sakura が usage オブジェクトに `prompt_tokens_details.cached_tokens` 等を含めない場合の挙動は v1.14 / main で同等（どちらも `nil` フォールバック）。`prompt_cache_miss_tokens` / `prompt_cache_hit_tokens` を見るのは DeepSeek 系互換のためで、Sakura に効くかは未検証。
- `lib/ruby_llm/chat.rb` のコールバックが additive 化（`before_message` / `after_message` 等）。`response.content` の構造化出力パース処理（後述§3）と `with_schema`（§2.3）は両バージョンで同一実装。
- 構造化出力の payload 形式 (`response_format: { type: 'json_schema', json_schema: { ... } }`) は v1.14 / main で同一。

→ **plan.md §4.2 が想定する v1.14 系の挙動をそのまま main の読解で代用してよい**。本メモは main を主として記述する。

---

## 1. 設定項目

### 1.1 OpenAI 互換エンドポイントを使う場合の最小設定

`lib/ruby_llm/providers/openai.rb:38-50` で OpenAI provider が公開する設定キーは:

```
openai_api_key             (必須: configuration_requirements)
openai_api_base            (任意: 未指定時 https://api.openai.com/v1)
openai_organization_id     (任意)
openai_project_id          (任意)
openai_use_system_role     (任意: 既定 nil → false 扱い)
```

Sakura 用の最小設定は実質 2 つ:

```ruby
RubyLLM.configure do |c|
  c.openai_api_key  = ENV['SAKURA_AI_API_KEY']
  c.openai_api_base = 'https://api.ai.sakura.ad.jp/v1'  # ← /v1 まで含む
end
```

`api_base` は `lib/ruby_llm/providers/openai.rb:17-19` で `@config.openai_api_base || 'https://api.openai.com/v1'`。Faraday の base_url としてそのまま渡され (`lib/ruby_llm/connection.rb:26`)、`completion_url` は `'chat/completions'` (`lib/ruby_llm/providers/openai/chat.rb:8-10`)。よって base に `/v1` を含めないと `https://api.ai.sakura.ad.jp/chat/completions` を叩いてしまう。**末尾スラッシュの有無は Faraday URL 結合に依存**するため、`/v1` で確定させる方が安全。

### 1.2 `openai_use_system_role` の意味

`lib/ruby_llm/providers/openai/chat.rb:135-142` で system メッセージのロールを切り替える。

```
:system → openai_use_system_role が truthy: 'system'
                            それ以外: 'developer'
```

既定値は `nil`（`Configuration.register_provider_options` 経由で `option :openai_use_system_role, nil`、`lib/ruby_llm/configuration.rb:17-19`、`lib/ruby_llm/providers/openai.rb:38-46`）。よって**何も設定しないと system メッセージが `developer` ロールで送られる**。OpenAI 公式 GPT-5 系/o-シリーズ向けの仕様。

**Sakura での実機検証結果**: probe `a_connect` (`tmp/probe_results/sakura__a_connect__gpt-oss-120b.json`) で `gpt-oss-120b` 上の system / developer 双方を直接送出し、いずれも HTTP 200・同一の prompt_tokens 数（90）で受理されることを確認した。Sakura 公式 OpenAPI（[ai-engine-inference-api.json](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json)）でも `developer` は `ChatCompletionRequestDeveloperMessage` の許容 enum として明示定義されている。RubyLLM 経由で `with_instructions` + developer 送出（`scenario_rubyllm_system_role_off`）でも応答取得を確認。指定の有無による差は本検証範囲では観測されなかった。検証範囲は `gpt-oss-120b` のみで、他モデル（`llm-jp-3.1-8x13b-instruct4` 等）は vLLM の chat template に依存するため個別検証が必要。RubyLLM の既定 `developer` 送出は OpenAI reasoning モデル仕様に準拠しているため、reasoning モデル以前の旧 `system` ロール挙動に固定したい場合や、`developer` を受け付けない OpenAI 互換サーバを併用する場合のみ `openai_use_system_role = true` を明示する。

### 1.3 認証ヘッダ

`lib/ruby_llm/providers/openai.rb:21-27`:

```
Authorization        : Bearer #{openai_api_key}
OpenAI-Organization  : ... (nil なら .compact で除去)
OpenAI-Project       : ... (同上)
```

さくら側で `OpenAI-Organization` / `OpenAI-Project` ヘッダを許可しないことは考えにくいが、未指定なら送信されないので問題なし。

### 1.4 タイムアウトとリトライ

`lib/ruby_llm/configuration.rb:46-50`:

```
request_timeout            : 300 (秒)
max_retries                : 3
retry_interval             : 0.1
retry_backoff_factor       : 2
retry_interval_randomness  : 0.5
```

リトライ対象は `lib/ruby_llm/connection.rb:102-114`:

- `Errno::ETIMEDOUT`, `Timeout::Error`, `Faraday::TimeoutError`, `Faraday::ConnectionFailed`, `Faraday::RetriableResponse`
- `RubyLLM::RateLimitError` (HTTP 429)
- `RubyLLM::ServerError` (HTTP 500)
- `RubyLLM::ServiceUnavailableError` (HTTP 502/503/504)
- `RubyLLM::OverloadedError` (HTTP 529)

特筆:

- リトライ対象 HTTP メソッドに `:post` が追加されている (`lib/ruby_llm/connection.rb:83`)。`chat/completions` も自動リトライされる。
- 429 が冪等にリトライされるため、Sakura 無償プランの月次クォータ超過時もバックオフして再送される。**意図しない多重課金/呼び出しに注意**。
- `request_timeout` の既定 300 秒は reasoning モデル想定。Sakura のモデルでもタイムアウトに当たるケースは限定的だが、巨大 MoE で長文生成すると到達しうる。

---

## 2. リクエスト構築

### 2.1 メッセージ組み立て

`Provider#complete` (`lib/ruby_llm/provider.rb:41-65`) が共通エントリ。`render_payload` 結果と `params` を `Utils.deep_merge` してから POST する。`with_params(**)` で渡した値が **provider が組んだ payload を上書き**する形。Sakura 固有のパラメータ（仮にあれば）は `with_params` で注入できる一方、`response_format` 等の構造化出力ペイロードまで上書きできてしまう。

`render_payload` (`lib/ruby_llm/providers/openai/chat.rb:14-52`) の組み立て:

```
{
  model: model.id,                # ← Models registry の resolve 後 ID
  messages: format_messages(...), # role/content/tool_calls/tool_call_id を compact + thinking
  stream: <ブロック有無>
}
+ temperature        (nil なら省略)
+ tools, tool_choice, parallel_tool_calls (tools.any? のとき)
+ response_format    (schema 指定時)
+ reasoning_effort   (with_thinking 時)
+ stream_options     (stream 時、 include_usage: true 固定)
```

メッセージ整形は `format_messages` (`lib/ruby_llm/providers/openai/chat.rb:124-133`) で `Media.format_content` を介す。テキストのみのときは `Media.format_content` が `String` をそのまま返すため、payload は `content: "..."` の純粋な文字列。テキスト + 添付があるときのみ OpenAI 仕様の配列形式 (`type: 'text'` / `'image_url'` / `'file'` / `'input_audio'`) に展開される (`lib/ruby_llm/providers/openai/media.rb:10-37`)。

### 2.2 ツール呼び出しのペイロード形式

`lib/ruby_llm/providers/openai/tools.rb:28-43` の `tool_for`:

```ruby
{
  type: 'function',
  function: {
    name: tool.name,
    description: tool.description,
    parameters: parameters_schema   # JSON Schema (object)
  }
}
```

特徴:

- パラメータ schema は `tool.params_schema || schema_from_parameters(tool.parameters)`。明示しないと `EMPTY_PARAMETERS_SCHEMA = { type: 'object', properties: {}, required: [], additionalProperties: false, strict: true }`（`lib/ruby_llm/providers/openai/tools.rb:10-16`）が入る。
- `tool.provider_params` が非空なら `Utils.deep_merge` で上書き可能 (`tools.rb:40-42`)。
- `tool_choice` (`tools.rb:103-115`):
  - `:auto`, `:none`, `:required` はシンボルそのまま
  - それ以外（特定 tool 名）は `{ type: 'function', function: { name: tool_choice } }` を生成
- `parallel_tool_calls` は `tool_prefs[:calls] == :many` で boolean 化（`chat.rb:27-28`）

→ さくら側 vLLM 等の tool parser が `tool_choice: required` や `parallel_tool_calls: false` を未対応とするケースがあれば、`with_tool(..., choice: :auto, calls: :many)` のみに絞る必要が出るかもしれない。

### 2.3 構造化出力（json_schema）のペイロード形式

`lib/ruby_llm/providers/openai/chat.rb:31-44`:

```ruby
payload[:response_format] = {
  type: 'json_schema',
  json_schema: {
    name: schema_name,
    schema: schema_def,
    strict: strict
  }
}
```

スキーマは `Chat#with_schema` (`lib/ruby_llm/chat.rb:106-114`) を経由し、`normalize_schema_payload` (`chat.rb:206-214`) で必ず `{ name, schema, strict, description? }` に正規化される:

- `schema[:strict]` が明示されていなければ `true`（`chat.rb:227-234` の `strict.nil? || strict`）
- `name` は `[^a-zA-Z0-9_-]` を `_` に置換 (`chat.rb:236-239`)、空なら `'response'`
- `RubyLLM::Schema` クラスは `to_json_schema` を持ち、`{ name, description, schema }` の Hash を返す（`ruby_llm-schema/lib/ruby_llm/schema/json_output.rb:6-26`）。`Schema` 自身は `additional_properties` 既定 `false`、`strict` 既定 `true` (`ruby_llm-schema/lib/ruby_llm/schema.rb:49-60`) を JSON Schema 内部に埋め込む

→ 結果として OpenAI 仕様にかなり厳密な payload が生成される。**さくら側の推論エンジン（vLLM の guided JSON 等）が `strict: true` および `additionalProperties: false` を完全に解釈する保証はない**。サーバが該当フィールドを単に無視する場合と、構文エラーで 400 を返す場合が想定される（要実機）。

### 2.4 Vision の image_url ペイロード

`lib/ruby_llm/providers/openai/media.rb:39-46`:

```ruby
{
  type: 'image_url',
  image_url: {
    url: image.url? ? image.source.to_s : image.for_llm
  }
}
```

`image.url?` が真なら URL 文字列をそのまま、偽なら `for_llm`（base64 data URI 想定）。Sakura のような閉じたインフラで外部 URL を fetch する設計でない場合、URL 渡しは失敗する可能性が高く、**さくらのAI Engine では base64 data URI 経由が無難**。

### 2.5 Streaming

- `Provider#complete` が `block_given?` で stream 切替 (`provider.rb:59-63`)
- `payload[:stream] = true` および `payload[:stream_options] = { include_usage: true }` を **必ず** 付与 (`openai/chat.rb:21, 49`)
- ストリーミング時は `OpenAI::Streaming#build_chunk` (`lib/ruby_llm/providers/openai/streaming.rb:14-35`) が SSE データを `Chunk` オブジェクトに変換
  - `data['choices'][0]['delta']` を見る。`delta['content']` が無ければ `data['choices'][0]['message']['content']` にフォールバック（非標準だが堅牢）
  - `delta['reasoning_content']` または `delta['reasoning']` を thinking として吸収
  - `tool_calls` のストリーミング差分は `parse_arguments: false` で文字列のまま伝播される (`streaming.rb:28`)
- `parse_streaming_error` (`streaming.rb:37-49`) は SSE データ中の `error.type` を見て `[status, message]` を返す。`server_error` → 500、`rate_limit_exceeded`/`insufficient_quota` → 429、その他 → 400

→ **Sakura が `stream_options.include_usage` を未対応のとき、リクエストを 400 で弾く可能性がある**。ストリーミング無効化の選択肢しか無い。`stream_options` を抑止するオプションは現状の RubyLLM には無いため、`with_params(stream_options: nil)` で潰そうとしても `Utils.deep_merge` の挙動次第（要検証）。

---

## 3. レスポンス処理

### 3.1 通常応答のパース

`OpenAI::Chat#parse_completion_response` (`lib/ruby_llm/providers/openai/chat.rb:54-82`):

1. `response.body` が空なら `nil` 返却（呼び出し側で nil 扱いになる経路あり）
2. `data['error']['message']` があれば `RubyLLM::Error` を raise
3. `data['choices'][0]['message']` から content / tool_calls / thinking を抽出
4. `Message.new(role: :assistant, content:, tool_calls:, ...)` で返す

**前提されているフィールド**:

- `choices[0].message`: 無いと `parse_completion_response` が `nil` を返し、後段で `NoMethodError` 系の事故になりうる
- `model`: `response['model']` を `Message#model_id` に格納（無くても動くが cost 計算で `model_info` が引けない）
- `usage`: 無くてもよい（`{}` フォールバック）が、ある場合は OpenAI フォーマット準拠を期待

### 3.2 tool_calls の解釈

`lib/ruby_llm/providers/openai/tools.rb:73-101`:

- `tool_call.function.arguments` を `JSON.parse`。`nil` または空文字列なら `{}`
- **`arguments` が壊れた JSON のとき `JSON::ParserError` をそのまま raise**（rescue 無し）。Sakura のモデルが不正な JSON を返すと例外で落ちる
- `id` をキーにした Hash として返す。`id` が `nil` だと Hash キーが `nil` で衝突しうる

### 3.3 構造化出力時の `response.content` の戻り型

`Chat#complete` (`lib/ruby_llm/chat.rb:172-178`):

```ruby
if @schema && response.content.is_a?(String) && !response.tool_call?
  begin
    response.content = JSON.parse(response.content)
  rescue JSON::ParserError
    # If parsing fails, keep content as string
  end
end
```

つまり:

- **schema 指定 + tool_call ではない場合**、`response.content` は JSON.parse 後の **Hash/Array**
- **JSON.parse に失敗した場合は文字列のまま黙って通過**（例外も警告も無し）
- 呼び出し側は型を見て分岐する必要がある。`response.content.is_a?(Hash)` で成功判定可能

**さくらのAI Engine で問題になりやすいパターン**:

- モデルが ` ```json ... ``` ` のような Markdown コードブロックで囲って返す → `JSON.parse` 失敗 → 文字列のまま戻る → 利用者は気づかない
- モデルが「JSON もどき」（末尾コンマ等）を返す → 同上
- 構造化出力 + tool_call の両立は分岐に乗らない（`!response.tool_call?` のため）。schema 指定中に tool_call が混入したら content は元のまま

### 3.4 `reasoning_content` 等の非標準フィールド

`OpenAI::Chat#extract_thinking_text` (`lib/ruby_llm/providers/openai/chat.rb:165-168`):

```
message_data['reasoning_content'] || message_data['reasoning'] || message_data['thinking']
```

の優先順で String を拾う。`extract_thinking_signature` (`170-173`) は `reasoning_signature` または `signature`。

ストリーミング側 (`streaming.rb:25`) も `delta['reasoning_content'] || delta['reasoning']` を見る。

加えて content が `<think>...</think>` 形式の文字列のときは `extract_think_tag_content` (`openai/chat.rb:210-217`) で本文と思考を分離。

→ **Sakura の gpt-oss-120b 等が reasoning を返す場合、`Message#thinking.text` で受けられる可能性が高い**（フィールド名が `reasoning_content` か `reasoning` か `<think>` タグ埋め込みかいずれかなら）。フォーマット未知の場合は無視される（content 側に混入する）。

### 3.5 usage オブジェクトの前提

`input_tokens` (`openai/chat.rb:84-91`)：`prompt_cache_miss_tokens` を最優先、なければ `prompt_tokens - cache_read - cache_write`。

`output_tokens` (`93-110`)：`completion_tokens` 基本だが `total_tokens - prompt_tokens` の方が大きければそちらを採用（reasoning tokens 包含時の補正）。

`cache_read_tokens` (`112-114`)：`prompt_tokens_details.cached_tokens` または `prompt_cache_hit_tokens`。

→ Sakura が `usage.prompt_tokens` / `usage.completion_tokens` のみを返すケースでは、token 数は素直に取れる。`prompt_tokens_details` 等が無くても `nil` 安全。

---

## 4. モデル解決

### 4.1 Models registry

- 実体は `lib/ruby_llm/models.json`（main で 1,251 モデル登録、61,457 行）。読み込みは `Models.read_from_json` (`lib/ruby_llm/models.rb:48-54`)
- **Sakura の API base 配下で提供されるモデル ID（`gpt-oss-120b`、`llm-jp-3.1-8x13b-instruct4`、`Qwen3-Coder-30B-A3B-Instruct`、`Phi-4`、`preview/Qwen3-VL-30B-A3B-Instruct` など）は registry に「Sakura provider のもの」としては登録されていない**（Sakura provider 自体が無い）
- 同名 ID（例: `gpt-oss-120b`）が `azure` / `bedrock` / `openrouter` 配下に存在するため、`Models.find('gpt-oss-120b')` は **provider を指定しないと `azure` 等の同名モデルを返してしまい**、その後 OpenAI provider のメソッドに渡らないことで構成不整合に至る恐れがある

### 4.2 `Chat.new` での解決経路

`Chat#initialize` → `with_model` (`lib/ruby_llm/chat.rb:71-75`) → `Models.resolve(model_id, provider:, assume_exists:, config:)`（`models.rb:106-137`）。

```
provider 指定 + assume_exists: true
  → Model::Info.default(model_id, provider_slug) を生成（registry 不参照）
provider 指定なし or assume_exists: false
  → Models.find(model_id, provider) で registry を引く
    見つからなければ ModelNotFoundError
```

`Model::Info.default` (`lib/ruby_llm/model/info.rb:11-20`) は:

```ruby
new(
  id: model_id,
  name: model_id.tr('-', ' ').capitalize,
  provider: provider,
  capabilities: %w[function_calling streaming vision structured_output],
  modalities: { input: %w[text image], output: %w[text] },
  metadata: { warning: 'Assuming model exists, capabilities may not be accurate' }
)
```

→ **Sakura 利用時は `assume_model_exists: true` + `provider: :openai` が事実上必須**:

```ruby
RubyLLM.chat(model: 'gpt-oss-120b', provider: :openai, assume_model_exists: true)
```

これを忘れると:

- `provider` 未指定なら `Models.find` が `azure:gpt-oss-120b` を返し、OpenAI provider ではなく Azure provider が呼ばれて API base が `azure_*` 系設定を要求する → `ConfigurationError`
- `provider: :openai` だけ指定して `assume_model_exists: false` だと `ModelNotFoundError` (`models.rb:478, 503`)

### 4.3 `assume_model_exists` の副作用

- `Model::Info.default` が **全 capability を `true` 扱いで返す**ため、`model.supports?('vision')` 等の事前チェックが信頼できなくなる
- `temperature` 正規化 (`lib/ruby_llm/providers/openai/temperature.rb:10-20`) は `model.id` に対して正規表現で判定するだけなので、`assume_model_exists: true` でも `gpt-5*` や `o1*` パターンに合致すると `temperature` が `1.0` 強制される可能性。Sakura の独自モデル ID では基本ノーヒットなので影響少ないが、OpenAI 公式モデル ID を Sakura 経由で叩いたら（理論上）副作用が出る

### 4.4 Chat 初期化と provider 必須要件

`Chat.new(assume_model_exists: true)` で **`provider` を渡さないと `ArgumentError`** (`lib/ruby_llm/chat.rb:11-13`)。さらに `Models.resolve` 内でも `assume_exists` 時に provider が無ければ `ArgumentError` (`models.rb:116`)。

---

## 5. エラーハンドリング

### 5.1 HTTP ステータスコード → 例外マッピング

`lib/ruby_llm/error.rb:65-99` の `ErrorMiddleware.parse_error`:

| status | 例外クラス | 既定メッセージ |
|---|---|---|
| 200..399 | （raise なし、message を返すのみ）| - |
| 400 | `BadRequestError` （context length 文言一致時 `ContextLengthExceededError`）| `Invalid request - please check your input` |
| 401 | `UnauthorizedError` | `Invalid API key - check your credentials` |
| 402 | `PaymentRequiredError` | `Payment required - please top up your account` |
| 403 | `ForbiddenError` | `Forbidden - you do not have permission to access this resource` |
| 429 | `RateLimitError`（context length 文言一致時 `ContextLengthExceededError`） | `Rate limit exceeded - please wait a moment` |
| 500 | `ServerError` | `API server error - please try again` |
| 502..504 | `ServiceUnavailableError` | `API server unavailable - please try again later` |
| 529 | `OverloadedError` | `Service overloaded - please try again later` |
| その他 | `RubyLLM::Error` | `An unknown error occurred` |

context length 判定 (`error.rb:53-63, 103-107`) は message に対する正規表現マッチ。`/context length/i`、`/context window/i`、`/maximum context/i`、`/request too large/i`、`/too many tokens/i`、`/token count exceeds/i`、`/input[_\s-]?token/i`、`/input or output tokens? must be reduced/i`、`/reduce the length of messages/i` のいずれかを含めば該当。**Sakura の context 超過エラーが日本語/独自表現で返ると検知されず、ただの 400/429 として扱われる**。

### 5.2 エラーメッセージ抽出

`Provider#parse_error` (`lib/ruby_llm/provider.rb:114-132`):

- body が JSON で `Hash` なら `body['error']` (String) または `body.dig('error', 'message')`
- Array なら各要素に同様の処理
- それ以外なら body をそのまま

→ Sakura が `{ "error": { "message": "..." } }` 形式を返すなら問題なし。`{ "detail": "..." }` のような FastAPI 流形式だと `nil` になり、上記既定メッセージが使われる（原因が見えにくい）。

### 5.3 認証失敗・モデル不在・パラメータ不正の症状差分

| 症状 | 例外 | 経路 |
|---|---|---|
| API key 未設定 | `RubyLLM::ConfigurationError` | `Provider#ensure_configured!` (`provider.rb:254-259`) または `Connection#ensure_configured!` (`connection.rb:116-128`) |
| API key 無効 | `UnauthorizedError` (HTTP 401) | サーバ応答 |
| モデル ID が registry に無い（assume_model_exists 未指定）| `ModelNotFoundError` | `Models#find_without_provider` (`models.rb:495-504`) / `find_with_provider` (`models.rb:473-479`) |
| モデル ID がサーバ未対応（registry には存在）| `BadRequestError` (HTTP 400) | サーバ応答 |
| パラメータ不正 | `BadRequestError` (HTTP 400) | サーバ応答 |
| ストリーミング中のサーバエラー | `parse_streaming_error` で status 番号化 → 上記マッピング | `streaming.rb:37-49` |

### 5.4 リトライとの相互作用

§1.4 で述べたとおり 429/500/502-504/529/Connection 系は自動でリトライされる（既定 3 回 + バックオフ）。**認証エラー (401) は再試行されない**ので即座に raise される。

---

## 6. Sakura 環境で特に注意すべき箇所

OpenAI 公式仕様を前提とし、さくらのAI Engine で問題化しうる箇所を優先度順に列挙。

### 6.1 system role を `developer` で送る既定挙動（参考）

`openai_use_system_role` を未設定だと `:system` ロールが `'developer'` 文字列で送出される（OpenAI reasoning モデル仕様準拠）。`gpt-oss-120b` での実機検証では system / developer ともに HTTP 200・同一 prompt_tokens で受理され、Sakura OpenAPI も `developer` を許容 enum として定義しているため、**指定なしでも本検証範囲では問題は観測されない**（詳細は §1.2）。reasoning モデル以前の旧 `system` ロール挙動に固定したい場合や、`developer` を受け付けない OpenAI 互換サーバを併用する場合のみ `openai_use_system_role = true` を明示する。他モデルは vLLM の chat template 依存のため未検証。

### 6.2 構造化出力 payload の strict / additionalProperties（高）

`with_schema` 経由のスキーマには **必ず `strict: true` および `additionalProperties: false` が埋め込まれる**（§2.3）。さくら側 vLLM の `guided_json` 経路がこれを完全には解釈しない場合、

- 200 が返って **schema 強制が効いていない**（自由形式の文字列）
- または `JSON.parse` 失敗時に `chat.rb:172-178` で **黙って文字列のまま返却**

の二段で失敗が見えなくなる。**呼び出し側で `response.content.is_a?(Hash)` を確認するアサーションを必ず入れる**ことが安全策。

### 6.3 `stream_options: { include_usage: true }` 強制（中）

ストリーミング時に常時付与（§2.5）。さくら側がこのフィールドを未対応で 400 にすると、ストリーミングは事実上使えない。回避策は `with_params` 経由の上書きを試すか、ストリーミング自体を諦めるか。

### 6.4 モデル ID 衝突と `assume_model_exists`（高）

§4.2 のとおり `gpt-oss-120b` は registry の azure/bedrock/openrouter 配下に存在する。`provider:` 未指定だと意図しない provider が解決される。**`provider: :openai, assume_model_exists: true` を必ず両方付ける**運用にする。`Configuration#default_model` (`'gpt-5.4'`) もそのままだと OpenAI 公式モデル扱いになるため、Sakura 用には触らないか別 default を持つ。

### 6.5 tool_calls の arguments パース失敗が例外（中）

§3.2。Sakura のモデルが function_calling 学習度の低いモデルで不正 JSON を返すと、`JSON::ParserError` が `Chat#complete` の上層まで貫通する。`begin/rescue JSON::ParserError` で囲うパターンを呼び出し側に置くか、構造化出力のときと違って **arguments パース失敗には RubyLLM 側のフォールバックは無い**点を許容する。

### 6.6 SSE エラーペイロードの形式前提（中）

`parse_streaming_error` (`streaming.rb:37-49`) は `error.type` が `'server_error'` / `'rate_limit_exceeded'` / `'insufficient_quota'` のいずれかを期待。Sakura が独自の `error.type` を返したら一律 400 扱い。リトライ対象から外れる可能性がある。

### 6.7 reasoning フィールド名のばらつき（中）

§3.4 のとおり `reasoning_content` / `reasoning` / `thinking` / `<think>` タグ のいずれかでないと拾えない。Sakura の gpt-oss-120b が別名（例: `reasoning_text`、`reasoning_summary` 等）で返すと、本文に混入するか欠落する。

### 6.8 `temperature` 自動正規化の流れ弾（低）

`Temperature.normalize` (`temperature.rb:10-20`) は **モデル ID の正規表現** で判定。Sakura のモデル ID（`gpt-oss-120b` 等）は基本ヒットしないので無害だが、`o3-...` や `gpt-5-...` といった命名を Sakura が今後採用するとサイレントに `temperature=1.0` が強制される。

### 6.9 リトライによる多重課金（低）

`POST /chat/completions` がリトライ対象。429 を受けても自動再送するため、有償プラン移行後は意図しない呼び出し回数増を招きうる。`max_retries: 0` で無効化可能。

### 6.10 vision の URL 渡しが失敗する可能性（低）

§2.4。`image.url?` 経路は外部 URL を fetch 可能なサーバ前提。Sakura が外部アクセス不可なら base64 経由（`Image.from_path` 等）に揃える。

---

## 7. 参照元一覧

- `lib/ruby_llm/configuration.rb`
- `lib/ruby_llm/connection.rb`
- `lib/ruby_llm/chat.rb`
- `lib/ruby_llm/provider.rb`
- `lib/ruby_llm/error.rb`
- `lib/ruby_llm/message.rb`
- `lib/ruby_llm/models.rb`
- `lib/ruby_llm/model/info.rb`
- `lib/ruby_llm/providers/openai.rb`
- `lib/ruby_llm/providers/openai/chat.rb`
- `lib/ruby_llm/providers/openai/tools.rb`
- `lib/ruby_llm/providers/openai/streaming.rb`
- `lib/ruby_llm/providers/openai/media.rb`
- `lib/ruby_llm/providers/openai/temperature.rb`
- `lib/ruby_llm/providers/openai/capabilities.rb`
- `lib/ruby_llm/providers/openai/models.rb`
- `lib/ruby_llm/models.json`（grep のみ）
- `ruby_llm-schema/lib/ruby_llm/schema.rb`
- `ruby_llm-schema/lib/ruby_llm/schema/json_output.rb`

### 取得失敗 / 未確認

- なし（必要ファイルはすべて取得済み）
- ただし `lib/ruby_llm/embedding.rb`、`providers/openai/embeddings.rb` はチャット範囲外のため本メモでは未読。さくらのAI Engine で embedding 利用時は別途読解が必要
