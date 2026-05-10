# Sakura AI Engine × RubyLLM トラブルシューティング集

- **最終確認日**: 2026-05-09
- **対象**: `ruby_llm` 1.15.0、Sakura AI Engine `https://api.ai.sakura.ad.jp/v1`
- **形式**: 各項目は「症状 → 原因 → 対処」の三段構成。再現コードを最小化して掲載

---

## TS-01: `RubyLLM::ModelNotFoundError` が出る

**症状**:
```ruby
RubyLLM.chat(model: 'gpt-oss-120b').ask('hello')
# => RubyLLM::ModelNotFoundError
```

**原因**: RubyLLM の models registry には Sakura のモデルが「Sakura provider のもの」としては登録されていない（Sakura provider 自体が存在しない）。`provider:` も `assume_model_exists:` も指定しないと、registry を引いた結果として例外になる。

**対処**:
```ruby
RubyLLM.chat(
  model: 'gpt-oss-120b',
  provider: :openai,           # ← 必須
  assume_model_exists: true    # ← 必須
)
```

---

## TS-02: 意図しない provider（Azure OpenAI 等）が解決される

**症状**: `assume_model_exists: true` を付けても、`gpt-oss-120b` を渡すと `ConfigurationError: azure_*` 系の設定が要求される。

**原因**: RubyLLM の `models.json` には `gpt-oss-120b` 等の同名モデルが Azure / Bedrock / OpenRouter 配下に既に登録されている。`provider:` を指定しないと `Models.find` が他 provider を返す。

**対処**: `provider: :openai` を **必ず** 明示する（TS-01 と組み合わせ）。

---

## TS-03: `BadRequestError: This model is not available.`

**症状**:
```ruby
RubyLLM.chat(model: 'Phi-4', provider: :openai, assume_model_exists: true).ask('hello')
# => RubyLLM::BadRequestError: This model is not available.
```

**原因**: 公式マニュアルの「ライセンス表」（S6）と「操作ガイド」（S5）で表記揺れがある。S6 のモデル名と実 API model 文字列は一致しない。例: S6 の `Phi-4-mini-instruct` は API では `preview/Phi-4-mini-instruct-cpu`（preview/ 付き、`-cpu` サフィックス付き）。

**対処**: `GET /v1/models` で実 API 文字列を取得して使う:
```ruby
require 'net/http'
uri = URI('https://api.ai.sakura.ad.jp/v1/models')
req = Net::HTTP::Get.new(uri)
req['Authorization'] = "Bearer #{ENV['SAKURA_AI_ACCOUNT_KEY']}"
resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
JSON.parse(resp.body)['data'].map { |m| m['id'] }
# => ["llm-jp-3.1-8x13b-instruct4", "preview/Qwen3-0.6B-cpu",
#     "preview/Phi-4-mini-instruct-cpu", ...]
```

なお、`/v1/models` は OpenAPI 仕様には未定義だが実装されている。

---

## TS-04: `with_schema` を使ったのに `response.content` が String

**症状**:
```ruby
class WeatherSchema < RubyLLM::Schema
  number :temperature_celsius
  string :condition
end

msg = chat.with_schema(WeatherSchema).ask('天気を返して')
msg.content.is_a?(Hash)  # => false（String）
msg.content              # => "申し訳ありませんが、リアルタイム情報には..." 等の自然文
```

**原因**: さくら側の推論エンジンは `response_format: json_schema` を **200 で受理するが、schema 強制を実機では一切行わない**。中立プロンプト「東京の架空の天気を返して」で検証 4 モデル（`gpt-oss-120b` / `llm-jp-3.1-8x13b-instruct4` / `Qwen3-Coder-30B-A3B-Instruct` / `preview/Phi-4-mini-instruct-cpu`）すべてで `response_format` の有無に関わらず自然文が返り、JSON にもならないことを確認済み（`tmp/probe_results/c_schema__*.json`）。RubyLLM 側は `with_schema` で OpenAI 仕様準拠の `response_format` を送出していること（webmock 検証済）から、原因は Sakura 側に固有。

モデルが自然文を返した場合、RubyLLM の `chat.rb:172-178` には JSON.parse 失敗時にサイレントフォールバック（文字列のまま返す）するコードがあるため、例外も警告も出ない。

プロンプト追従を試した場合のモデル別傾向（互換性検証ではなく利用上の参考）:
- `gpt-oss-120b`: フィールド名・JSON 旨を明示すれば JSON 風 Hash を返すが値レベル制約は守らない（TS-05）
- `Qwen3-Coder-30B-A3B-Instruct`: 同様に Hash 化はするが日本語訳が混入（TS-05）
- `llm-jp-3.1-8x13b-instruct4`: プロンプトで指示しても長文自然文に流れがち
- `preview/Phi-4-mini-instruct-cpu`: ` ```json ... ``` ` の Markdown コードブロックで返す（パース失敗）

**対処**: `with_schema` を「スキーマ強制機構」として使えない前提で、(1) プロンプト本文で出力形式（フィールド名、JSON 旨）を明示、(2) 呼び出し側でアサート、(3) Hash 化されても値レベル検証を別途実施する。

```ruby
unless msg.content.is_a?(Hash)
  raise "Schema not enforced; got #{msg.content.class}: #{msg.content.inspect[0, 200]}"
end
```

加えて、Hash であっても enum や required が満たされている保証はないので、値レベルの検証も別途必要（dry-validation 等）。

---

## TS-05: プロンプトで JSON 指示しても enum 違反値が返る

**症状**: TS-04 の対処として「プロンプトで JSON で答えるよう明示する」と Hash 化に成功するが、値が enum を守らない。
さくら側
```ruby
# enum: %w[sunny cloudy rainy snowy] のはずが
msg.content   # => { "temperature_celsius" => 22, "condition" => "partly cloudy" }
```

**原因**: TS-04 と同根。Sakura 側で `response_format` の `strict: true` も `additionalProperties: false` も無視されており、schema 強制機構は実質存在しない。プロンプトでフィールド名や JSON 旨を指示すれば `gpt-oss-120b` は JSON 風 Hash を返し、`Qwen3-Coder-30B-A3B-Instruct` も Hash 化はするが、値レベル制約はモデルの訓練分布次第（`Qwen3-Coder-30B` は `"曇り"` 等の日本語訳が混入）。

**対処**: アプリ側で値レベルの検証層を持つ。例:
```ruby
ALLOWED = %w[sunny cloudy rainy snowy]
unless ALLOWED.include?(msg.content['condition'])
  # 再生成プロンプトを投げる、または fallback
end
```

---

## TS-06: `response.content` が `null`（応答が空）

**症状**: raw HTTP で `gpt-oss-120b` に短いプロンプトを送ると `choices[0].message.content` が `null`、`finish_reason` が `length`。

**原因**: `gpt-oss-120b` は **reasoning モデル** で、応答に `reasoning_content` フィールドが含まれる。`max_tokens` が小さいと reasoning_content だけで使い切られて、本文 `content` を生成する前にカットされる。

```json
{
  "choices": [{
    "message": {
      "content": null,
      "reasoning_content": "User wants random number 0-9 printed..."
    },
    "finish_reason": "length"
  }]
}
```

**対処**:
- `max_tokens` を最低でも数百〜数千に設定する
- raw HTTP で受ける場合は `reasoning_content` の存在を前提にパースする
- RubyLLM 経由なら `Message#thinking` で reasoning を受け取れる（`openai/chat.rb:165-168` の `extract_thinking_text`）

---
さくら側
## TS-07: `BadRequestError: "auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser ...`

**症状**: `with_tool` を使うと特定モデルで上記エラー。
- 該当: `llm-jp-3.1-8x13b-instruct4`、`preview/Phi-4-mini-instruct-cpu`

**原因**: Sakura 側の vLLM サーバが、これらのモデルに対しては `--enable-auto-tool-choice` フラグ無しで起動されている。RubyLLM の `with_tool` は既定 `tool_choice: auto` を送るためエラーになる。

**対処**:
- `Qwen3-Coder-30B-A3B-Instruct` または `gpt-oss-120b` を使う（auto OK）
- どうしても当該モデルで使いたい場合は `tool_choice` を `:required` または特定 tool 名に固定:
  ```ruby
  chat.with_tool(MyTool, choice: :required)  # tool_prefs[:choice] = :required
  ```
- `preview/Phi-4-mini-instruct-cpu` は `auto` で HTTP 400（同 vLLM エラー）、`required`/`named` で HTTP 500 `Upstream server error` を返す。**tools パラメータを送ると挙動が不安定**になるため tool 利用は事実上不可。`tool_choice: none` も probe では HTTP 500 だが、過去に 200 で自然文応答が返った観察例あり（再現性が安定しない）

---
さくら側
## TS-08: `tool_choice: 'none'` を指定したのに tool_call が出る

**症状**: `tool_choice: 'none'` で送ったのに、`finish_reason: 'tool_calls'` で tool_call が返る。
- 該当: `gpt-oss-120b`

**原因**: さくら側の推論エンジンで `tool_choice: 'none'` の解釈が未実装のように見える挙動。`auto` と同じ扱いになっている可能性。

**対処**: `tools` 自体を渡さない（none を効かせたい場面では tools パラメータを送らない）。

---

## TS-09: content に `<tool_call>...</tool_call>` の生 XML が漏れる

**症状**: `Qwen3-Coder-30B-A3B-Instruct` で `tool_choice: 'none'` を送ると、`message.content` に Qwen 内部表現の XML が混入:
```text
<tool_call>
<function=get_weather>
<parameter=city>
東京
</parameter>
</function>
</tool_call>
```

**原因**: Qwen 系モデル固有の tool 呼び出し表現が、`tool_choice: 'none'` で tool_calls 配列に整形されないまま content にそのまま流れている。推論エンジン側で Qwen の tool 表現の整形と `tool_choice: none` の解釈が未実装のように見える挙動。

**対処**:
- TS-08 と同じく、tools 自体を渡さない
- または content から正規表現で `<tool_call>...</tool_call>` を除去する後処理を入れる

---

## TS-10: `n: 2` を送ったのに `choices` が 1 件しか返らない

**症状**:さくら側
```ruby
RubyLLM.chat(...).with_params(n: 2).ask('hello')
# choices=1 のみ
```

**原因**: さくら側で `n` パラメータが未実装のような挙動（OpenAPI にも未定義）。受理されるが効果なし。

**対処**: 同じ chat オブジェクトに対して 2 回 `ask` を呼ぶ。temperature を上げて多様性を確保する。

---さくら側

## TS-11: `temperature: 99.9` 等の不正値が 200 で通る

**症状**: OpenAPI 仕様では `temperature: 0..2` と定義されているが、`temperature: 99.9` を送っても 400 にならず 200 が返る。`max_tokens: 10_000_000` も同様。

**原因**: Sakura 側で OpenAPI 制約のサーバ側バリデーションが行われていない。

**対処**: クライアント側で範囲検証する。RubyLLM の `with_temperature` 等を経由する場合も範囲チェックは無いため、設定値をハードコードしない構成では別途バリデーションを入れる。

---

## TS-12: 401 `Unauthorized` または `Invalid token`

**症状**: `RubyLLM::UnauthorizedError`。

**原因と対処**:
| 原因 | 対処 |
|---|---|
| トークン未設定 | `RubyLLM.config.openai_api_key` を確認 |
| トークン形式の誤り | Sakura のトークンは `<UUID>:<シークレット>` の形式。コピペで `:` の前後を削っていないか確認 |
| トークン失効 | コントロールパネルで再発行 |
| メッセージで原因切り分け | 401 `Unauthorized`（Authorization ヘッダ無し）/ `Invalid token`（ヘッダはあるが値が NG） |

**注意**: 401 はリトライ対象外（`connection.rb:102-114`）なので、即座に raise される。

---

## TS-13: stream で usage chunk が来る／来ない

**症状**: streaming 利用時に最後のほうで `delta` が空で `usage` だけ入った chunk が混入。

**原因**: RubyLLM は `stream_options: { include_usage: true }` を **常時** 付与する（`openai/chat.rb:49`、`stream` フラグの設定自体は同 :21）。さらに Sakura は include_usage の指定有無に関わらず usage chunk を送ってくる。

**対処**: 通常はパースが正しく動くため対処不要。独自に SSE をパースしている場合は `data['choices']` が空のチャンクをスキップする実装を入れる:
```ruby
next if parsed.dig('choices', 0, 'delta', 'content').nil? && !parsed['usage']
```

---

## TS-14: tool_call の `arguments` JSON が壊れていて `JSON::ParserError`

**症状**: `chat.ask` 中に `JSON::ParserError` が貫通する。

**原因**: モデルが返した `tool_calls[0].function.arguments` の文字列が JSON として不正。RubyLLM の `tools.rb:73-101` には JSON.parse の rescue が **無い**（構造化出力時のサイレントフォールバックとは違う）。

**対処**:
- function_calling の学習度が高いモデル（`gpt-oss-120b` / `Qwen3-Coder-30B-A3B-Instruct`）を使う
- 呼び出し側で `JSON::ParserError` を rescue:
  ```ruby
  begin
    chat.with_tool(MyTool).ask(prompt)
  rescue JSON::ParserError => e
    # フォールバック処理
  end
  ```

---

## TS-15: system プロンプトが効いていないように見える

**症状**: `chat.with_instructions('簡潔に返して').ask(...)` で長い回答が返る。

**原因（候補）**:
1. モデル側の system プロンプト追従度の差。`gpt-oss-120b` のような MoE は短い system プロンプトに対する追従度が公式 OpenAI モデルと異なる。
2. `openai_use_system_role` が `nil`（既定）だと system メッセージが `developer` ロールとして送出される（`openai/chat.rb:135-142`）が、Sakura 公式 OpenAPI で `developer` は許容 enum として定義されており、probe `a_connect` で `gpt-oss-120b` 上では system / developer 双方が同一の prompt_tokens 数（90）で 200 受理されることを確認済み。少なくとも `gpt-oss-120b` では「ロールが原因で system プロンプトが効かなくなる」現象は観測されていない。他モデル（llm-jp-3.1 等）は vLLM の chat template に依存するため未検証。

**対処**:
- 第一の対処: user メッセージ側に指示を集約する（`'簡潔に返して。質問: ...'`）
- 旧来の `system` ロール挙動に固定したい場合のオプション（既定の `developer` 送出は OpenAI reasoning モデル仕様準拠のため、reasoning モデル以外の挙動に揃えたい場合や `developer` 非対応の OpenAI 互換サーバ併用時に使用）:
  ```ruby
  RubyLLM.configure do |c|
    c.openai_use_system_role = true   # system → 'system' ロール送出に固定
  end
  ```

---

## TS-16: Vision で画像が認識されない／誤認される

**症状**: `Qwen3-VL` または `Phi-4-multimodal` に画像を渡したが期待した認識結果にならない。

**原因と対処**:
| 原因 | 対処 |
|---|---|
| 画像が小さすぎる | 224×224 以上を推奨。48×48 では `preview/Phi-4-multimodal-instruct` は `Debian ロゴ` を「スパイラル」と誤認した実例あり |
| モデル選択ミス | `preview/Qwen3-VL-30B-A3B-Instruct` の方が小画像でも判別精度が高い |
| 外部 URL のホスト到達性 | OpenAPI は base64 限定の記述だが実機では外部 HTTPS URL も受理される。プライベートネットワーク内画像は NG |
| プロンプトの曖昧さ | 「この画像を説明して」より「ロゴが何か答えて」のように具体化 |

---

## TS-17: 無償枠超過のレート制限挙動

**症状**: 無償プランで連続呼出するうちに 429 が返るようになる。

**原因**: Sakura 無償枠は chat completions が **3,000 req/月**（公式 S12）。超過時は「レート制御」がかかる（具体値は公式記載なし）。

**対処**:
- RubyLLM は 429 を自動リトライする（`max_retries: 3` 既定）。**従量課金プランに切り替えていると意図せず多重課金される可能性**:
  ```ruby
  RubyLLM.configure do |c|
    c.max_retries = 0  # リトライ無効化
  end
  ```
- 月次のリクエスト数を独自カウンタで監視する
- 429 受信時は `RubyLLM::RateLimitError` で捕捉し、ジョブ単位で停止する

---さくら側

## TS-18: タイムアウトが既定 300 秒で長すぎる／短すぎる

**症状**: 巨大プロンプトで 300 秒超え、または短く打ち切りたい。

**原因**: RubyLLM の `request_timeout` 既定は 300 秒（`configuration.rb:46`）。Sakura 側のタイムアウトは公式記載なし（OpenAPI に 504 が定義されているのでサーバ側にも存在）。

**対処**:
```ruby
RubyLLM.configure do |c|
  c.request_timeout = 60   # 短縮例
end
```

---

## TS-19: preview/ モデルが急に消えた・名称が変わった

**症状**: 昨日まで動いていた `preview/Qwen3-...` が `BadRequestError: This model is not available.`

**原因**: preview モデルは公式に SLA や提供終了通知方針が明示されていない（公式マニュアル全体で該当記載なし）。

**対処**:
- 本番依存しない。preview モデルは PoC・実験のみ
- アプリ側で起動時に `GET /v1/models` で利用可能性を確認し、グレースフルに別モデルへフォールバックする

---

## TS-20: ENV 変数名が記事/サンプルとズレる

**症状**: 公式 / 個人 Zenn 記事のサンプルは Python の `OPENAI_API_KEY` 等を使う傾向だが、本プロジェクトは `SAKURA_AI_ACCOUNT_KEY`。コピペで動かない。

**原因**: 公式は ENV 名を規約化していない。

**対処**: チームで統一する。本リポジトリは `SAKURA_AI_ACCOUNT_KEY` で統一（`.env.example` を整備するなら同じ名前で）。

---

## 索引（症状 → 項目番号）

| 症状キーワード | 番号 |
|---|---|
| ModelNotFoundError | TS-01 |
| 意図しない provider | TS-02 |
| This model is not available | TS-03 |
| schema 効かない（自然文） | TS-04 |
| schema 効かない（enum 違反） | TS-05 |
| content が null | TS-06 |
| auto tool choice requires --enable-auto-tool-choice | TS-07 |
| tool_choice: none が無視される | TS-08 |
| `<tool_call>` が漏れる | TS-09 |
| n が効かない | TS-10 |
| temperature 制約値が効かない | TS-11 |
| 401 Unauthorized | TS-12 |
| streaming で usage chunk | TS-13 |
| tool_call arguments JSON 壊れ | TS-14 |
| system プロンプトが効かない | TS-15 |
| 画像認識誤り | TS-16 |
| 429 / rate limit | TS-17 |
| timeout | TS-18 |
| preview モデル消失 | TS-19 |
| ENV 名のズレ | TS-20 |
