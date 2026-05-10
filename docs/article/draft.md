---
title: "「OpenAI 互換」の境界線を引く: RubyLLM × さくらのAI Engine の API 互換性ガイド"
emoji: "🧭"
type: "tech"
topics: ["ruby", "rails", "rubyllm", "llm", "sakura"]
published: false
publication_name: "takeyuwebinc"
---

**さくらのAI Engine**（以下 Sakura）の「OpenAI 互換」は、HTTP リクエストの受理性と成功時応答の基本構造では成立しますが、振る舞いが公式 OpenAI と完全一致するレベルでは成立しません。Sakura 公式 OpenAPI と公式 OpenAI 実機の比較では、`tool_choice: none`／OpenAPI 数値制約の強制／エラー応答構造／`response_format` で非互換が確定します。これに加えて、`tool_choice: named` の `finish_reason`、応答ボディの拡張フィールド、streaming の usage chunk、vision の文言と実機の差という注意点があります。さらに **RubyLLM** 1.15.0 を OpenAI 互換クライアントとして Sakura に向けると、registry の同名モデル衝突、`with_schema` のサイレント String 化、429 の自動リトライ、system ロールの `developer` 変換という、クライアント実装側に起因する罠があります。本記事はこれらの差分と、本番投入前に置くべき防御点を具体的なコードで提示します。

:::message
この記事の執筆にあたり、AI による支援（レビュー、文章の整形、ファクトチェック）を受けています。内容の正確性については可能な限り筆者が確認していますが、もしも誤りを見つけた場合はコメントでお知らせ頂けると嬉しいです。
:::

:::message
**最終確認日**: 2026-05-09 / **検証環境**: Ruby 4.0.2、`ruby_llm` 1.15.0（commit `ff392893bb5366937688fa82bc0841185491f84c`）。Sakura 側のモデル更新・サーバ構成変更で挙動は変わります。半年〜1 年での再確認を推奨します。
:::

## 解決策サマリー: 安全に動かすための最小設定

`gpt-oss-120b` への基本チャットだけ通れば良い場合は、次の設定で完結します。

```ruby:config/initializers/ruby_llm.rb
RubyLLM.configure do |c|
  c.openai_api_key  = ENV.fetch('SAKURA_AI_ACCOUNT_KEY')   # <UUID>:<シークレット>
  c.openai_api_base = 'https://api.ai.sakura.ad.jp/v1'     # 末尾の /v1 まで含める
  c.openai_use_system_role = true                          # system → developer 変換を抑止（後述「system ロールの developer 変換」節を参照）
  c.max_retries = 0                                        # 429 自動リトライによる多重課金を回避。ただし 503・ネットワークエラーの再送も同時に無効化する点に注意（後述「429 を自動リトライする」節を参照）
end
```

```ruby
chat = RubyLLM.chat(
  model: 'gpt-oss-120b',
  provider: :openai,            # registry の同名モデル衝突回避（後述「registry の同名モデル ID 衝突」節を参照）
  assume_model_exists: true     # registry 未登録モデルを暫定 capability で解決（後述「registry の同名モデル ID 衝突」節を参照）
)
chat.ask('こんにちは')
```

この最小設定で、基本チャット・streaming・`tool_choice: auto` の経路は動作します。一方、`with_schema` を「型安全な構造化出力」として使う設計、`tool_choice: none` でツール呼び出しを止める設計、`error.code` でエラー分岐する設計はいずれも壊れます。なお `c.max_retries = 0` は 429 だけでなく 503・ネットワークエラーの自動再送も同時に止めるため、サマリーだけコピペすると一時エラーへの再送が消える点に注意してください。背景は以降の節で解説します。

## 「OpenAI 互換」の二段構え: どこまでが互換か

「OpenAI 互換」と書かれていれば `base_url` 差し替えだけで同じコードが動く、という見立ては部分的にしか成立しません。Sakura 公式 OpenAPI 仕様（[ai-engine-inference-api.json](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json)）と公式 OpenAI 実機を比較すると、互換は「同じクライアントで叩ける」と「振る舞いが一致する」の二段に分かれます。本記事の各論はそのどちらの段階の問題かを基準に配置しています。

### 「同じ OpenAI 互換クライアントで叩ける」レベルは成立する

Bearer トークンによる認証、`POST /v1/chat/completions` への JSON リクエスト、`stream: true` での SSE chunked 応答、`tool_choice: auto` 指定時の `tool_calls` 配列と `finish_reason: tool_calls`、`image_url` への外部 HTTPS URL ／ base64 data URI 双方の 200 受理は、`bin/probe` の実機ログでも公式 OpenAI と一致しています（`tmp/probe_results/` 配下の各 `__a_connect__` `__d_tools__` `__e_streaming__` `__f_vision__` JSON）。OpenAI SDK や RubyLLM を `base_url` 差し替えで Sakura に向けるパターンは、「最低限のチャット完了が回るか」の判定では合格します。

### 「振る舞いが完全一致する」レベルは成立しない

一方、パラメータの強制、エラー応答の構造、特定モードの解釈、応答ボディのフィールド集合に踏み込むと、Sakura は公式 OpenAI と異なる挙動を返します。`temperature: 99.9` を 200 で受理し、不明モデル ID には 404 ではなく 400 を返し、エラーボディに `type` / `param` / `code` を含めず、`tool_choice: none` を無視して `tool_calls` を返し、応答 message に `reasoning_content` や `function_call`（公式 OpenAI で deprecated 化済み）を混ぜます。

加えて、Sakura 公式 OpenAPI 仕様の `POST /v1/chat/completions` は `responses.200` が `description: Success` のみでレスポンススキーマを持たず、エラーボディの JSON 構造も定義されていません。リクエスト側の `temperature: 0..2`、`max_tokens: minimum 1` といった数値制約は OpenAPI に明示されているもののランタイムでは強制されません（`tmp/probe_results/sakura__g_errors__gpt-oss-120b.json` の `invalid_temperature` / `huge_max_tokens` シナリオ）。OpenAPI を契約として読んでクライアントを自動生成しても、レスポンス構造・エラーボディ・数値制約のいずれも契約から外れます。

差分は HTTP の受理性、レスポンス構造、制約の強制、エラー応答という別々のレイヤに散らばるため、本記事では契約レベル（後述「Sakura が公式 OpenAI と異なる4箇所」「Sakura で気をつけるべき4つの差異」）と RubyLLM クライアント実装（後述「RubyLLM 側に潜む4つの罠」）に分けて配置します。

## Sakura が公式 OpenAI と異なる4箇所（非互換）

ここからの 4 点は、Sakura `gpt-oss-120b` と公式 OpenAI `gpt-4o-mini` の実機比較で確定した非互換です。クライアント側で分岐・抑止・バリデーションを置かないと、公式 OpenAI で動いていたコードが Sakura で意図と違う動き方をします。各小節は「症状 → なぜ起こるか → RubyLLM での対処コード」で揃えています。

### `tool_choice: none` が無視される

**症状**: `tool_choice: 'none'` を指定したのに、応答に `tool_calls` が含まれ `finish_reason: tool_calls` で終わります。公式 OpenAI `gpt-4o-mini` は同条件で `has_tool_calls: false`、`finish_reason: stop` を返し、自然文（"東京の現在の天気を取得します。少々お待ちください。"）で応答します（`tmp/probe_results/sakura__d_tools__gpt-oss-120b.json` と `tmp/probe_results/openai__d_tools__gpt-4o-mini.json` の `raw_tools_none` シナリオを比較）。

**なぜ起こるか**: Sakura 公式 OpenAPI の `ChatCompletionToolChoiceOption` は `none` を含む 4 値を enum として定義していますが、推論エンジン側で `none` の解釈が動いていません。応答ボディに `prompt_logprobs` / `kv_transfer_params` / `reasoning_content` といった vLLM 系の拡張フィールドが含まれていることから、Sakura は内部で vLLM 系の OSS 推論エンジンを採用していると推測されます。その推論エンジンの起動オプションやパーサ設定で `none` 経路が拾われていないと読み取れます。

**RubyLLM での対処コード**: tool を呼ばせたくない場面では `tools` パラメータ自体を渡しません。tool を載せた chat と載せない chat を別オブジェクトで持ちます。

```ruby
# tool が必要な経路
chat_with_tool = RubyLLM.chat(model: 'gpt-oss-120b', provider: :openai, assume_model_exists: true)
chat_with_tool.with_tool(GetWeather).ask('東京の天気を教えて')

# tool を絶対に呼ばせたくない経路
chat_plain = RubyLLM.chat(model: 'gpt-oss-120b', provider: :openai, assume_model_exists: true)
chat_plain.ask('東京の天気を会話で教えて')   # tools を渡さない
```

`tool_choice: 'none'` を信頼した実装は Sakura で破綻するため、コードレベルで「tools を渡さない」に倒します。

### OpenAPI の数値制約が実機で強制されない

**症状**: Sakura OpenAPI に `temperature: 0..2`、`max_tokens: minimum 1` が明示されているにもかかわらず、`temperature: 99.9` と `max_tokens: 10_000_000` のいずれも HTTP 200 で受理されます。公式 OpenAI `gpt-4o-mini` は同条件で 400 を返し、`error.message: "Invalid 'temperature': decimal above maximum value. Expected a value <= 2, but got 99.9 instead."` のように具体的な原因を示します（`tmp/probe_results/openai__g_errors__gpt-4o-mini.json` の `invalid_temperature` シナリオ）。

**なぜ起こるか**: Sakura 側 API ゲートウェイ層に OpenAPI 制約のサーバ側バリデーションが実装されていないと考えられます。`temperature: 99.9` を送ったときに何が起きるかは推論エンジン側の解釈次第で、`finish_reason: length` で `content` が空になる、reasoning だけ消費して content が `null` になる、などの予測しづらい結果に流れます（前述の probe ログ `invalid_temperature` シナリオでは `content: null`、`finish_reason: length` を確認）。

**RubyLLM での対処コード**: クライアント側で範囲検証を入れます。RubyLLM は `with_temperature` 等を経由する場合も範囲チェックを行いません。

```ruby
class SafeChat
  TEMPERATURE_RANGE = (0.0..2.0)
  MAX_TOKENS_RANGE  = (1..16_384)

  def self.ask(prompt, temperature: 1.0, max_tokens: 1024)
    raise ArgumentError, "temperature out of range: #{temperature}" \
      unless TEMPERATURE_RANGE.cover?(temperature)
    raise ArgumentError, "max_tokens out of range: #{max_tokens}" \
      unless MAX_TOKENS_RANGE.cover?(max_tokens)

    chat = RubyLLM.chat(model: 'gpt-oss-120b', provider: :openai, assume_model_exists: true)
    chat.with_temperature(temperature)
        .with_params(max_tokens: max_tokens)
        .ask(prompt)
  end
end
```

`MAX_TOKENS_RANGE` の上限はモデル依存です。Sakura 側に厳密な上限が公開されていないため、ここでは公式 OpenAI 互換の運用上現実的な値（公式 OpenAI `gpt-4o-mini` は 16,384 を上限として 400 を返す。probe ログ `tmp/probe_results/openai__g_errors__gpt-4o-mini.json` の `huge_max_tokens` シナリオ参照）に揃える例として置いています。実利用では用途に合わせて狭めて構いません。

### エラー応答の HTTP ステータス・ボディ構造

**症状**: 不明モデル ID で chat を実行すると、Sakura は HTTP 400、公式 OpenAI は HTTP 404 を返します。エラーボディは Sakura が `{"error":{"message":"This model is not available."}}` のみで、公式 OpenAI が一貫して提供する `type` / `param` / `code` を含みません。

| シナリオ | Sakura | 公式 OpenAI |
|---|---|---|
| Authorization ヘッダ無し | 401 `{"error":{"message":"Unauthorized"}}` | 401 `{"error":{"message":"...","type":"invalid_request_error","param":null,"code":null}}` |
| 不正トークン | 401 `{"error":{"message":"Invalid token"}}` | 401 `{"error":{"message":"...","type":"invalid_request_error","param":null,"code":"invalid_api_key"}}` |
| 不明モデル ID | **400** `{"error":{"message":"This model is not available."}}` | **404** `{"error":{"message":"...","type":"invalid_request_error","param":null,"code":"model_not_found"}}` |
| `temperature` 範囲外 | **200**（受理） | **400** `{"error":{"message":"...","param":"temperature","code":"decimal_above_max_value"}}` |

ソース: `tmp/probe_results/sakura__g_errors__gpt-oss-120b.json`、`tmp/probe_results/openai__g_errors__gpt-4o-mini.json`。

**なぜ起こるか**: Sakura OpenAPI の `responses` 定義に 404 が含まれず、エラーボディの `type` / `param` / `code` も構造定義されていないため、Sakura 側で省略されています。RubyLLM の例外マッピングは HTTP コードに基づくため、不明モデルが 400 で返ってきた Sakura では `RubyLLM::BadRequestError`、404 で返ってきた公式 OpenAI では汎用 `RubyLLM::Error` というずれが発生します（probe ログ `rubyllm_unknown_model` シナリオ）。

**RubyLLM での対処コード**: エラー分岐は HTTP ステータス由来の RubyLLM 例外クラスのみで行い、`error.code` や `error.type` の値には依存しません。

```ruby
def safe_chat(prompt)
  chat = RubyLLM.chat(model: 'gpt-oss-120b', provider: :openai, assume_model_exists: true)
  chat.ask(prompt)
rescue RubyLLM::UnauthorizedError
  # 401: Sakura は "Unauthorized" / "Invalid token"、OpenAI は "Incorrect API key provided..."
  # メッセージで分岐せず、常に「鍵を確認」のフローに倒す
  notify_admin_about_auth_failure
  raise
rescue RubyLLM::BadRequestError => e
  # 400: Sakura では「不明モデル」「サーバ側起動オプション欠如」も 400 で来る。
  # error.code が nil 前提で、メッセージ文字列のキーワードのみで分類する
  case e.message
  when /not available/i           then handle_unknown_model
  when /enable-auto-tool-choice/i then fallback_without_auto_tool
  else raise
  end
rescue RubyLLM::Error => e
  # 公式 OpenAI で 404 が来た場合のフォールバック（Sakura では発生しない）
  raise unless e.message.include?('does not exist')
  handle_unknown_model
end
# 429 のハンドリングは後述「429 を自動リトライする」節を参照
```

`error.code` を見て分岐するロジックは Sakura では `nil` に当たって常に else に流れるため、HTTP ステータス由来の例外クラスとメッセージ文字列のキーワードを併用します。

### `response_format`（`json_schema`）が効かない

**症状**: `RubyLLM::Schema` を使った `chat.with_schema(WeatherSchema).ask(...)` で `response_format: json_schema` を送出しても、Sakura の応答は schema を反映しません。中立プロンプト「東京の架空の天気を返して」を Sakura `gpt-oss-120b` に送ると、`response_format` を渡しても渡さなくても Markdown 表の自然文が返り、JSON ですらありません。

**なぜ起こるか**: Sakura 公式 OpenAPI の `POST /v1/chat/completions` requestBody に `response_format` プロパティの記述がありません。`response_format: json_schema` は OpenAI Structured Outputs の中核機能（[OpenAI Structured Outputs 公式ガイド](https://platform.openai.com/docs/guides/structured-outputs)）で、推論エンジン側の constrained decoding（JSON Schema 違反となるトークン候補を逐次マスクする仕組み）が動いて初めて schema が強制されます。Sakura 側でこの経路が有効化されておらず、リクエストは 200 で受理されながら schema は無視されます。

RubyLLM 側の送信ペイロードは webmock で捕捉すると `{"type":"json_schema","json_schema":{"name":"WeatherSchema","schema":{...},"strict":true}}` の形で送出されており、クライアントの送り方は OpenAI 仕様どおりです。

**RubyLLM での対処コード**: `with_schema` を「型安全な構造化出力」として信頼せず、戻り値型を必ずアサートします。Sakura 側で schema が効かない結果、モデルが自然文を返すと RubyLLM 内部で `JSON.parse` に失敗し、サイレントフォールバックで `String` がそのまま返ります（この挙動は後述「`with_schema` は JSON.parse 失敗時に String を返す」節で詳述）。

```ruby
class WeatherSchema < RubyLLM::Schema
  number :temperature_celsius
  string :condition, enum: %w[sunny cloudy rainy snowy]
end

msg = chat.with_schema(WeatherSchema).ask('東京の架空の天気を返して')

unless msg.content.is_a?(Hash)
  raise "Schema not enforced; got #{msg.content.class}: #{msg.content.inspect[0, 200]}"
end

# Hash であっても enum / required は満たされている保証がない
allowed = %w[sunny cloudy rainy snowy]
unless allowed.include?(msg.content['condition'])
  raise "Invalid condition: #{msg.content['condition']}"
end
```

回避策として「プロンプト本文で JSON 形式・フィールド名を文章で指示する」方針も取れますが、モデル別に追従の癖（JSON 風 Hash で返す／Markdown コードブロックで包む／長文の自然文で返す）が出るため、値レベルのバリデーションは別途必要です。

## Sakura で気をつけるべき4つの差異（注意）

ここからの 4 点は、互換は保たれているが想定と異なる挙動です。なかには「応答ボディに OpenAPI 仕様外のフィールドが含まれる」のように RubyLLM 経由なら実害が出ない情報共有項目も含まれます。実害が大きい順ではなく、引っかかりやすさで並べています。

### `tool_choice: named` の `finish_reason` 差

**症状**: `tool_choice: { type: "function", function: { name: "get_weather" } }` を指定したとき、`tool_calls` 配列の中身（関数名・引数）は両者一致しますが、`finish_reason` が Sakura `tool_calls` / OpenAI `stop` で異なります（probe ログ `raw_tools_named`: `tmp/probe_results/sakura__d_tools__gpt-oss-120b.json` と `tmp/probe_results/openai__d_tools__gpt-4o-mini.json`）。

**なぜ起こるか**: 公式 OpenAI は `tool_choice: named` を「指定 tool を 1 回呼び出したら自然な終端」（=`stop`）として扱い、Sakura は「tool_calls 配列を返したので終端」（=`tool_calls`）として扱います。tool 呼び出し自体はどちらも正しく出力されます。

**RubyLLM での対処コード**: 会話終端の判定を `finish_reason` 単独に依存せず、`tool_calls` の有無で見ます。

```ruby
msg = chat.with_tool(GetWeather, choice: 'get_weather').ask('東京の天気')

if msg.tool_calls && !msg.tool_calls.empty?
  # tool 呼び出しがあった。finish_reason の値（stop か tool_calls か）に依存しない
  execute_tool_calls(msg.tool_calls)
elsif msg.content && !msg.content.empty?
  # 自然文応答
  display(msg.content)
end
```

### 応答ボディに OpenAPI 仕様外のフィールドが含まれる

**症状**: Sakura の応答 JSON は、公式 OpenAI の応答にないフィールドを含みます。

| 階層 | Sakura `gpt-oss-120b` のキー | 公式 OpenAI `gpt-4o-mini` のキー |
|---|---|---|
| top-level | `id`, `object`, `created`, `model`, `choices`, `service_tier`, `system_fingerprint`, `usage`, **`prompt_logprobs`**, **`prompt_token_ids`**, **`kv_transfer_params`** | `id`, `object`, `created`, `model`, `choices`, `usage`, `service_tier`, `system_fingerprint` |
| `message` | `role`, `content`, `refusal`, `annotations`, `audio`, **`function_call`**, **`tool_calls`**, **`reasoning_content`** | `role`, `content`, `refusal`, `annotations` |

太字は公式 OpenAI の chat completion 応答に存在しない／非推奨のフィールドです。データ出典: `tmp/probe_results/sakura__a_connect__gpt-oss-120b.json` および `tmp/probe_results/openai__a_connect__gpt-4o-mini.json`。

**なぜ起こるか**: `prompt_logprobs` / `prompt_token_ids` / `kv_transfer_params` は vLLM の chat completion 拡張（[vLLM 公式ドキュメント: OpenAI 互換サーバ](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html)）と一致します。`function_call` は OpenAI 公式リファレンスで [deprecated と明記](https://developers.openai.com/api/reference/python/resources/chat/subresources/completions) されている旧フィールドで、`tool_calls` への移行が指示されています。`reasoning_content` は reasoning モデルの思考過程を入れる vLLM 拡張で、vLLM 本体は [Reasoning Outputs](https://docs.vllm.ai/en/latest/features/reasoning_outputs/) で `reasoning` フィールドにリネーム済みですが、Sakura 側のバージョンでは `reasoning_content` のまま残っているとみられます。Sakura OpenAPI の `responses.200` がスキーマ定義を持たないため、厳密には「仕様違反」とは言えません。

**RubyLLM での対処コード**: RubyLLM 自体は未知フィールドを無視するため、ライブラリ経由ではこの差は見えません。`reasoning_content` は RubyLLM の `Message#thinking` で取得可能です（[`providers/openai/chat.rb#L165-L168`](https://github.com/crmne/ruby_llm/blob/ff392893bb5366937688fa82bc0841185491f84c/lib/ruby_llm/providers/openai/chat.rb#L165-L168) の `extract_thinking_text`）。raw HTTP で応答 JSON を直接パースする独自実装を併用している場合、未知フィールド許容のパーサ（strict mode を切る、未知キーを無視する）を使います。

```ruby
# RubyLLM 経由なら追加の対処は不要
msg = chat.ask('質問')
msg.thinking  # gpt-oss-120b の reasoning_content を取得

# 自前で JSON パースする場合、strict-typed なライブラリは避ける
# 例: dry-struct で strict なら attribute :prompt_logprobs, optional のように許容する
```

### streaming `usage` chunk の既定送信

**症状**: `stream: true` で `stream_options.include_usage` を指定しなくても、Sakura は終端付近で `usage` chunk を送ってきます。公式 OpenAI は `include_usage: true` を明示しないと送りません（probe ログ `raw_stream_no_usage`: `tmp/probe_results/sakura__e_streaming__gpt-oss-120b.json`、`tmp/probe_results/openai__e_streaming__gpt-4o-mini.json`。Sakura `usage_chunk_seen: true` / OpenAI `usage_chunk_seen: false`）。

**なぜ起こるか**: Sakura 側の SSE 実装は usage chunk を既定で送出する設定です。OpenAI 互換クライアントが余分な chunk を受け取るだけで互換性自体には反しません。RubyLLM は `stream_options: { include_usage: true }` を常時付与する実装（[`providers/openai/chat.rb#L49`](https://github.com/crmne/ruby_llm/blob/ff392893bb5366937688fa82bc0841185491f84c/lib/ruby_llm/providers/openai/chat.rb)）で、RubyLLM 経由なら usage chunk を前提に組まれており実害はありません。

**RubyLLM での対処コード**: RubyLLM のストリーミング API を素直に使えば対処不要です。SSE を独自にパースする実装を持っている場合、`data['choices']` が空で `usage` だけ入った chunk をスキップします。

```ruby
chat.ask('長めの応答を生成') do |chunk|
  print chunk.content if chunk.content   # nil チェックで usage chunk を素通し
end
```

独自パース時は次のように書きます。

```ruby
# 自前の SSE パーサで chunk を処理する場合
parsed = JSON.parse(line.delete_prefix('data: '))
next if parsed.dig('choices', 0, 'delta', 'content').nil? && !parsed['usage']
# 通常 chunk の処理
```

### vision `image_url` 文言と実機受理の差

**症状**: Sakura 公式 OpenAPI の `ChatCompletionRequestMessageContentPartImage` は `image_url.url` を「MIME タイプ情報を付与した base64 エンコードされた画像データ」と記述しており、外部 HTTPS URL の取扱いには言及がありません。一方、実機では外部 HTTPS URL も base64 data URI も両方 200 で受理されます（probe ログ `tmp/probe_results/sakura__f_vision__preview_Qwen3-VL-30B-A3B-Instruct.json`）。

**なぜ起こるか**: 公式 OpenAI の vision ガイドは「fully qualified URL / Base64-encoded data URL / file ID」の 3 方式を許容しており（[公式 vision ガイド](https://developers.openai.com/api/docs/guides/images-vision)）、Sakura の実機挙動は OpenAI と同じです。Sakura OpenAPI 仕様書の文言が実機より狭く書かれているだけと推測されます。

**RubyLLM での対処コード**: 外部 HTTPS URL に依存した実装は、Sakura 側の仕様書改訂で削除される可能性を考慮します。RubyLLM の `chat.ask(prompt, with: image_path)` を使えばローカルファイルは内部で base64 化されます（[`providers/openai/media.rb#L39-L46`](https://github.com/crmne/ruby_llm/blob/ff392893bb5366937688fa82bc0841185491f84c/lib/ruby_llm/providers/openai/media.rb#L39-L46)）。可能な範囲で base64 経路を併用しておくと、仕様変更時の影響を抑えられます。具体的には、ローカルファイルや自社ストレージから取得できる画像は base64、第三者 URL のみ取得元の制約で外部 HTTPS URL を使う、といった切り分けが安全です。

```ruby
chat = RubyLLM.chat(
  model: 'preview/Qwen3-VL-30B-A3B-Instruct',
  provider: :openai,
  assume_model_exists: true
)

# ローカルファイルを RubyLLM 経由で渡す（自動で base64 化）
chat.ask('この画像に何が写っていますか？', with: 'tmp/images/sample.png')
```

## RubyLLM 側に潜む4つの罠

ここからの 4 点は、RubyLLM 1.15.0 が OpenAI 互換クライアントとして汎用化されているために生まれる挙動です。Sakura 以外の OpenAI 互換 API（Groq、TogetherAI 等）でも当たる罠ですが、Sakura に切り替えたとき特に表面化しやすい組み合わせを取り上げます。

### registry の同名モデル ID 衝突

**症状**: `RubyLLM.chat(model: 'gpt-oss-120b').ask('hello')` を `provider:` 省略で実行すると、`RubyLLM::ModelNotFoundError`、または `assume_model_exists: true` を付けた状態で `ConfigurationError: azure_*` のような Sakura と無関係な設定要求が出ます。

**なぜ起こるか**: RubyLLM の [`models.json`](https://github.com/crmne/ruby_llm/blob/ff392893bb5366937688fa82bc0841185491f84c/lib/ruby_llm/models.json) には `gpt-oss-120b` などの同名モデル ID が Azure / Bedrock / OpenRouter など複数 provider 配下で登録済みです。`provider:` を指定しないと `Models.find` が他 provider を返し、その provider の設定（`azure_api_key` など）を要求して落ちます。Sakura は RubyLLM の registry に独立登録されていないため、OpenAI 互換クライアントとして `provider: :openai` で叩く必要があります。

**RubyLLM での対処コード**: `provider: :openai` と `assume_model_exists: true` を必須化します。後者は registry 未登録モデルを `Model::Info.default` で主要 capability（`function_calling` / `streaming` / `vision` / `structured_output`）を `true` 扱いの暫定 Info として扱います（[`model/info.rb#L11-L20`](https://github.com/crmne/ruby_llm/blob/ff392893bb5366937688fa82bc0841185491f84c/lib/ruby_llm/model/info.rb#L11-L20)）。`audio` などこの配列に含まれない capability の `supports?` は `false` を返します。毎回書くのを避けたい場合はヘルパーメソッドで隠蔽します。

```ruby
module SakuraChat
  def self.new(model:, **opts)
    RubyLLM.chat(model: model, provider: :openai, assume_model_exists: true, **opts)
  end
end

SakuraChat.new(model: 'gpt-oss-120b').ask('こんにちは')
```

`assume_model_exists: true` は capability チェック（vision / tools 対応の事前検証等）を素通しします。RubyLLM の事前バリデーションに依存していたコードは、Sakura 経路では別途検証してください。

### `with_schema` は JSON.parse 失敗時に String を返す

**症状**: `chat.with_schema(WeatherSchema).ask('天気を返して')` の戻り値で `msg.content.is_a?(Hash)` が `false` になり、`msg.content` には自然文の `String` がそのまま入ります。例外も警告も出ません。

**なぜ起こるか**: RubyLLM の `chat.rb` には `JSON.parse` 失敗時のサイレントフォールバックがあります（[`chat.rb#L172-L178`](https://github.com/crmne/ruby_llm/blob/ff392893bb5366937688fa82bc0841185491f84c/lib/ruby_llm/chat.rb#L172-L178)）。以下は `lib/ruby_llm/chat.rb` の `parse_content` 相当の要約です。

```ruby:lib/ruby_llm/chat.rb
# ruby_llm-1.15.0 の該当部分（要約）
def parse_content(text)
  return text unless schema?
  JSON.parse(text)
rescue JSON::ParserError
  text   # ← パース失敗時は String のままフォールバック
end
```

公式 OpenAI なら `response_format: json_schema strict: true` の constrained decoding で出力が必ず JSON になるためこのフォールバックはほぼ起動しませんが、Sakura で `response_format` が効かない（前節「`response_format`（`json_schema`）が効かない」を参照）と、モデルが自然文を返した瞬間にフォールバックが走り、`with_schema` の戻り値が想定の Hash でなく String で返ってきます。

**RubyLLM での対処コード**: サイレントフォールバックを検出するために `is_a?(Hash)` で最小アサートを入れて即時 raise します。値レベルのバリデーション（enum・required）の例は前節「`response_format`（`json_schema`）が効かない」に示したコードを参照してください。

```ruby
class SchemaNotEnforced < StandardError; end

msg = chat.with_schema(WeatherSchema).ask(prompt)

unless msg.content.is_a?(Hash)
  raise SchemaNotEnforced, "expected Hash, got #{msg.content.class}: #{msg.content.inspect[0, 200]}"
end
```

### 429 を自動リトライする: 多重課金リスク

**症状**: 無償プラン超過で 429 が返ったとき、RubyLLM が自動でリトライし、結果として複数回のリクエストが従量課金プランで請求される経路ができます。

**なぜ起こるか**: RubyLLM の `connection.rb` は Faraday の retry middleware を 429 を含む例外群で有効化しています（[`connection.rb#L102-L114`](https://github.com/crmne/ruby_llm/blob/ff392893bb5366937688fa82bc0841185491f84c/lib/ruby_llm/connection.rb#L102-L114)）。POST も自動リトライ対象で、既定 `max_retries: 3` で計 4 回リクエストが飛びます。429 を受けても自動再送が走る経路があるため、Sakura のプランで従量課金が有効化されている環境では、再送ぶんも課金対象になる可能性があります。Sakura の無償枠の上限・課金仕様の詳細は[公式マニュアル: 操作ガイド](https://manual.sakura.ad.jp/cloud/ai-engine/03-operation-guide.html)を参照してください。401 は retry 対象外なので即 raise されます。

**RubyLLM での対処コード**: 本番では `c.max_retries = 0` を設定するか、429 を外で即時停止します。

```ruby:config/initializers/ruby_llm.rb
RubyLLM.configure do |c|
  c.openai_api_key  = ENV.fetch('SAKURA_AI_ACCOUNT_KEY')
  c.openai_api_base = 'https://api.ai.sakura.ad.jp/v1'
  c.openai_use_system_role = true
  c.max_retries = 0   # 429 / 503 等の自動再送を無効化
end
```

`max_retries = 0` は 503 など一時エラーへの自動再送も無効化します。RubyLLM 1.15 の Configuration には特定例外のみ無効化するオプションがないため、429 のみを止めて 503 はリトライしたい場合は `RubyLLM::Connection#retry_exceptions` を monkey patch で上書きするか、レスポンスを外側で監視して 429 検出時に処理を停止する設計にします。

```ruby
# 429 のみを retry 対象から外す例（monkey patch、ruby_llm 1.15.0 で動作未検証）
module RubyLLM
  class Connection
    def retry_exceptions
      # 元実装から RateLimitError を除く（実装は ruby_llm のバージョンを確認すること）
      super.reject { |klass| klass == RubyLLM::RateLimitError }
    end
  end
end
```

monkey patch は RubyLLM 側の内部 API 変更で壊れる可能性があるため、本番投入前に `connection.rb` の現行実装を確認してください。バージョンを上げる際は同じファイル ([`connection.rb`](https://github.com/crmne/ruby_llm/blob/ff392893bb5366937688fa82bc0841185491f84c/lib/ruby_llm/connection.rb)) の `retry_exceptions` 周辺を確認します。

### system ロールの `developer` 変換

**症状**: `chat.with_instructions('簡潔に返して').ask(...)` で長文が返り、system プロンプトが効いていないように見えます。

**なぜ起こるか**: RubyLLM の `openai_use_system_role` が既定（`nil`）だと、system メッセージが `developer` ロール文字列で送出されます（[`providers/openai/chat.rb#L135-L142`](https://github.com/crmne/ruby_llm/blob/ff392893bb5366937688fa82bc0841185491f84c/lib/ruby_llm/providers/openai/chat.rb#L135-L142)）。公式 OpenAI の新仕様（一部モデルで `system` から `developer` へ移行）に向けた挙動ですが、Sakura 側のモデルが `developer` ロールを system と同じ重みで扱う保証はありません。Sakura OpenAPI（[ai-engine-inference-api.json](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json)）には `developer / system / user / assistant / tool` の 5 ロールが enum で定義されているものの、解釈の差は仕様書からは読み取れません。

**RubyLLM での対処コード**: `c.openai_use_system_role = true` を明示します。

```ruby:config/initializers/ruby_llm.rb
RubyLLM.configure do |c|
  c.openai_use_system_role = true   # system → 'system' ロールで送出
end
```

それでも system プロンプトが効かない場合は、user メッセージ側に指示を集約します（モデル側の system 追従度の問題で、ロール変換とは別の現象）。

```ruby
chat.ask('簡潔に返して。質問: 東京の天気')
```

## 本番投入前のチェックリスト

これまでの非互換・注意点・RubyLLM 側の罠を、コードに落としたかどうかの確認項目として並べます。各項目は本記事内の該当節への内部リンクを併記しています。

- [ ] `RubyLLM.chat(provider: :openai, assume_model_exists: true)` を必須化（[registry の同名モデル ID 衝突](#registry-の同名モデル-id-衝突)）
- [ ] `c.openai_use_system_role = true` を設定（[system ロールの `developer` 変換](#system-ロールの-developer-変換)）
- [ ] `c.max_retries = 0` を設定するか、429 を外側で即時停止する設計（[429 を自動リトライする: 多重課金リスク](#429-を自動リトライする-多重課金リスク)）
- [ ] エラー分岐は HTTP ステータス由来の RubyLLM 例外クラスのみで行い、`error.code` には依存しない（[エラー応答の HTTP ステータス・ボディ構造](#エラー応答の-http-ステータスボディ構造)）
- [ ] `temperature` `max_tokens` をクライアント側で範囲検証する（[OpenAPI の数値制約が実機で強制されない](#openapi-の数値制約が実機で強制されない)）
- [ ] `with_schema` の戻り値を `is_a?(Hash)` でアサート、enum / required は別途バリデーション（[`response_format`（`json_schema`）が効かない](#response_formatjson_schema-が効かない) / [`with_schema` は JSON.parse 失敗時に String を返す](#with_schema-は-jsonparse-失敗時に-string-を返す)）
- [ ] tool 抑制は `tool_choice: none` で表現せず、tools パラメータ自体を渡さない経路に倒す（[`tool_choice: none` が無視される](#tool_choice-none-が無視される)）
- [ ] streaming パーサは `usage` chunk が `include_usage` 無指定でも来る前提（[streaming `usage` chunk の既定送信](#streaming-usage-chunk-の既定送信)）

これらは Sakura に閉じない、RubyLLM 1.x を OpenAI 互換エンドポイントで使う際の共通ガードでもあります。Groq や TogetherAI など他の OpenAI 互換 API に切り替える場合も、同じチェック項目で振る舞いを再確認すると、互換性退行の検出が早くなります。

## まとめ

「OpenAI 互換」は「同じクライアントで叩ける」レベルは成立しますが、振る舞い一致は成立しません。Sakura 側の非互換と注意点、RubyLLM 1.15.0 側の罠は独立した発生源を持つため、契約レベルかクライアント実装かを切り分けて防御する必要があります。実務的な防御策は、HTTP ステータスを軸にした例外分岐・戻り値型のアサート・自動再送の停止に集約され、前述のチェックリストがそのまま実装ガードとして使えます。

時点性: 本記事は **2026-05-09 検証**のスナップショットです。Sakura は GA 開始から 8 ヶ月程度で、仕様書／実装の整合性は今後改善される可能性があります。半年〜1 年での再確認を推奨します。検証用 probe スクリプト (`bin/probe`) を `bundle exec bin/probe <feature> --provider sakura` で再実行し、`tmp/probe_results/` の旧結果と diff すれば差分が機械的に拾えます。

## 付録: 検証環境と参照

本記事の内容を再現・検証するための環境情報、モデル別の挙動概要、関連する一次資料を以下にまとめます。

### 検証環境

検証時に使用したランタイム・ライブラリ・モデルの構成は次のとおりです。

| 項目 | 値 |
|---|---|
| 検証日 | 2026-05-09 〜 2026-05-10 |
| Ruby | 4.0.2 |
| `ruby_llm` | 1.15.0 (commit `ff392893bb5366937688fa82bc0841185491f84c`) |
| `ruby_llm-schema` | 0.3.0 |
| Sakura 検証モデル | `gpt-oss-120b`（chat）/ `preview/Qwen3-VL-30B-A3B-Instruct`（vision） |
| OpenAI 検証モデル | `gpt-4o-mini` |

### モデル別の挙動差（簡易）

本記事は API 互換性に主眼を置くため、モデル別の挙動深掘りは扱いません。本検証で確認できた範囲を 1 行ずつ示すに留めます。詳細は本リポジトリ内のファイル `docs/reports/compatibility-matrix.md` を参照してください。

- `gpt-oss-120b` (GA reasoning): 基本チャット・streaming・tools (`auto`/`required`/`named`) すべて 200。`reasoning_content` で `max_tokens` を消費しやすいため最小でも 1024 を推奨
- `llm-jp-3.1-8x13b-instruct4` (GA 日本語 MoE): 基本チャット・streaming は 200。`tool_choice: auto` は推論エンジン側オプション欠如で 400 (`"auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser to be set`)
- `Qwen3-Coder-30B-A3B-Instruct` (GA コード MoE): 基本機能・tools すべて 200。`tool_choice: none` 時に Qwen 内部表現の `<tool_call>...</tool_call>` XML が `content` に漏れる
- `Qwen3-Coder-480B-A35B-Instruct-FP8` (GA): 30B 系列と機能挙動が近いと推測されるため、無償枠抑制のもと 30B を代表値として採用しました（実機未検証）
- `preview/Phi-4-mini-instruct-cpu` (preview 小型): 通常チャット・streaming は通るが、tools パラメータを渡すと `auto` で 400、`required`/`named` で 500 と不安定
- `preview/Qwen3-VL-30B-A3B-Instruct` (preview vision): 外部 URL／base64 双方 200。`tmp/images/sample.png`（48×48 Debian ロゴ PNG）を「Debianのロゴです。」と認識
- `preview/Phi-4-multimodal-instruct` (preview vision): 同画像で「『debianian』のロゴ画像です。」のように名称認識精度が劣る（応答はサンプリングごとに揺らぐ）

### 参考資料

一次資料および本リポジトリ内の補助資料は以下のとおりです。

- [さくらの AI Engine Inference API 仕様（JSON）](https://manual.sakura.ad.jp/api/cloud/portal/openapis/ai-engine-inference-api.json)
- [さくらの AI Engine マニュアル](https://manual.sakura.ad.jp/cloud/manual-ai-engine.html)
- [さくらの AI Engine 利用手順](https://manual.sakura.ad.jp/cloud/ai-engine/02-howto.html)
- [OpenAI Structured Outputs 公式ガイド](https://platform.openai.com/docs/guides/structured-outputs)
- [OpenAI vision ガイド](https://developers.openai.com/api/docs/guides/images-vision)
- [vLLM 公式ドキュメント: OpenAI 互換サーバ](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html)
- [vLLM 公式ドキュメント: Reasoning Outputs](https://docs.vllm.ai/en/latest/features/reasoning_outputs/)
- 本リポジトリ内: `docs/reports/sakura-openapi-vs-openai-compatibility.md`（Sakura 公式 OpenAPI vs 公式 OpenAI 互換性調査）
- 本リポジトリ内: `docs/reports/compatibility-matrix.md`（互換性マトリクス）
- 本リポジトリ内: `docs/reports/troubleshooting.md`（トラブルシューティング 20 項目）
- 本リポジトリ内: `lib/probes/`（検証 probe スクリプト）
