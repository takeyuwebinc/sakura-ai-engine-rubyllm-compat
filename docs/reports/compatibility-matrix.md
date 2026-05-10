# Sakura AI Engine × RubyLLM 互換性マトリクス

- **最終確認日**: 2026-05-09
- **対象 API**: `https://api.ai.sakura.ad.jp/v1`
- **検証 gem**: `ruby_llm` 1.15.0 (main / `ff392893bb...`), `ruby_llm-schema` (main)
- **検証 Ruby**: 4.0.2
- **代表モデル**: `gpt-oss-120b`（plan.md §3.5.3）
- **検証ログ**: `tmp/probe_results/*.json`（probe スクリプト: `lib/probes/`）

---

## 1. 表の凡例

| 記号 | 意味 |
|---|---|
| ✅ | 公式に明示／実機で完全に動く |
| ☑️ | 公式に明示はないが実機では動く（隠れ機能） |
| ⚠️ | 動くが部分的・条件付き・要注意 |
| ❌ | 公式に非サポート明示／実機で動かない |
| — | 該当しない／未検証 |

「公式 docs」は Sakura 公式マニュアル本文 + OpenAPI 仕様（`ai-engine-inference-*.yaml`）の合算。  
「API 受理」は HTTP 200 が返るか。  
「実機 enforcement」は **意図した効果が実際に発生するか**（200 が返ることと別問題）。

---

## 2. 機能 × 公式・実機 マトリクス（モデル非依存層）

| # | 機能 | 公式 docs | API 受理 | RubyLLM 抽象化 | 実機 enforcement | 注釈 |
|---|---|---|---|---|---|---|
| A | 接続・認証（Bearer Token） | ✅ | ✅ | ✅ | ✅ | `openai_api_base` に `/v1` を含める。トークン形式は `<UUID>:<シークレット>` |
| B | モデル指定 | ⚠️ | ✅ | ⚠️ | ✅ | 公式表記揺れあり（後述）。RubyLLM は `provider: :openai, assume_model_exists: true` 両方必須 |
| B' | `GET /v1/models` | ❌ OpenAPI 未定義 | ☑️ | — | ☑️ | **OpenAPI に定義はないが実装あり**。`/v1/models` でモデル一覧取得可 |
| E | Streaming（SSE） | ✅ | ✅ | ✅ | ✅ | `stream_options.include_usage` を付けなくても usage chunk が来る |
| G | エラーハンドリング | ✅ HTTP コード | ✅ | ✅ 例外マッピング正常 | ⚠️ | OpenAPI 上の `temperature: 0..2`、`max_tokens: minimum 1` 等の **制約値は実機では強制されない**（`temperature: 99.9`、`max_tokens: 10_000_000` も 200） |
| H | 基本パラメータ受理性 | △ 部分的 | ✅ 全て受理 | — | ⚠️ | 後述 §6 |

---

## 3. モデル一覧の実機確定（B 項目の詳細）

`GET /v1/models` 実行結果（2026-05-09 取得、`tmp/probe_results/v1_models.json`）:

### チャット系モデル

| 実 API model 文字列 | 区分 | 検証対象 |
|---|---|---|
| `gpt-oss-120b` | GA | ★ 代表モデル |
| `llm-jp-3.1-8x13b-instruct4` | GA | ★ |
| `Qwen3-Coder-30B-A3B-Instruct` | GA | ★ |
| `Qwen3-Coder-480B-A35B-Instruct-FP8` | GA | △（30B 版で代表取れるため簡易） |
| `preview/Qwen3-0.6B-cpu` | preview | △ |
| `preview/Phi-4-mini-instruct-cpu` | preview | ★ |
| `preview/Qwen3-VL-30B-A3B-Instruct` | preview (vision) | ★ |
| `preview/Phi-4-multimodal-instruct` | preview (vision) | ★ |

### Embeddings / Audio

| モデル | 用途 |
|---|---|
| `multilingual-e5-large` | embeddings |
| `preview/Qwen3-Embedding-4B-FP16` | embeddings |
| `whisper-large-v3-turbo` | audio transcription |

### 公式表記揺れの解決

| 公式マニュアル記載 | 実 API 文字列 | 差分 |
|---|---|---|
| `Phi-4-mini-instruct`（S6） | `preview/Phi-4-mini-instruct-cpu` | preview/ プレフィックス + `-cpu` サフィックス |
| `Qwen3-0.6B`（S6） | `preview/Qwen3-0.6B-cpu` | 同上 |
| `Qwen3-VL-30B-A3B-Instruct`（S6） | `preview/Qwen3-VL-30B-A3B-Instruct` | preview/ プレフィックス |
| `Phi-4-multimodal-instruct`（S6） | `preview/Phi-4-multimodal-instruct` | preview/ プレフィックス |
| `Phi-4`（plan.md §3.5.1）| `preview/Phi-4-mini-instruct-cpu` | 別物（`Phi-4` という文字列は API では未提供） |
| `Kimi-K2.5`（S6） | （未提供） | ライセンス表に記載があるが /v1/models に存在しない |

> **権威ソース**: Sakura 公式の S6 ライセンス表は API model 文字列の権威ソースではない。**API レイヤでの正しいモデル文字列は `GET /v1/models` で取得すべき**。

---

## 4. C: 構造化出力（response_format / json_schema）

### 4.1 検証方法

OpenAI API 互換性として「`response_format` パラメータが enforcement として機能しているか」を切り分けるため、プロンプトには出力形式（JSON / フィールド名）を一切含めず「東京の架空の天気を返して」のみを送る。判定基準は次の二点:

1. `response_format` を渡したときと渡さないときで、出力形式が変化するか
2. 渡したときに、スキーマに準拠した JSON が返るか

プロンプトで「JSON で答えて」と指示してしまうと JSON が返っても API パラメータの効果かプロンプト追従かを切り分けられないため、中立プロンプトの判定のみを互換性根拠として採用する（probe: `lib/probes/c_schema.rb`、ログ: `tmp/probe_results/c_schema__*.json`）。

### 4.2 RubyLLM 送信 payload の形状検証（webmock）

`with_schema(WeatherSchema)` の送出 payload を webmock で捕捉した結果（probe `c_schema` 内 `rubyllm_payload_shape` シナリオ）、4 モデル全てで以下の OpenAI 仕様準拠ペイロードが確認できた:

```json
"response_format": {
  "type": "json_schema",
  "json_schema": {
    "name": "WeatherSchema",
    "schema": { "type": "object", "properties": {...},
                "required": [...], "additionalProperties": false },
    "strict": true
  }
}
```

つまり**クライアント側（RubyLLM）の実装は OpenAI 仕様に準拠している**。以降の §4.3 の挙動は、さくら側で `response_format` 経路が未実装のように見える点に起因する。

### 4.3 公式・抽象化レベル

| 項目 | 状況 |
|---|---|
| 公式マニュアル本文 | ❌ `response_format` / `json_schema` の文字列が一切ない |
| OpenAPI 仕様 | ❌ `response_format` プロパティ未定義 |
| API 受理 | ☑️ 全モデルで 200 が返る |
| RubyLLM `with_schema` | ✅ OpenAI 仕様準拠の payload を送出（§4.2） |
| さくら側 enforcement | ❌ 全モデルで無視（§4.4） |

### 4.4 モデル × 実機 enforcement（中立プロンプト）

スキーマ定義（共通）: `{ temperature_celsius: number, condition: enum[sunny,cloudy,rainy,snowy] }`、`required: [temperature_celsius, condition]`、`additionalProperties: false`。プロンプトは中立 (`東京の架空の天気を返して`)。

| モデル | `response_format` 無し | `response_format: json_schema (strict:true)` | RubyLLM `with_schema` |
|---|---|---|---|
| `gpt-oss-120b` | Markdown 表（自然文） | Markdown 表（**変化なし**） | `String`（サイレント失敗） |
| `llm-jp-3.1-8x13b-instruct4` | 長文自然文 | 長文自然文（**変化なし**） | `String`（サイレント失敗） |
| `Qwen3-Coder-30B-A3B-Instruct` | 自然文 | 自然文（**変化なし**） | `String`（サイレント失敗） |
| `preview/Phi-4-mini-instruct-cpu` | 自然文 | 自然文（**変化なし**） | `String`（サイレント失敗） |

ログ: `tmp/probe_results/c_schema__*.json`（`compat_verdict.sakura_enforces_response_format: false` が全モデル共通）。

### 4.5 重要発見

- **`response_format: { type: 'json_schema', strict: true }` を送ってもさくら側の推論エンジンに反応がなく、`response_format` 経路は未実装のような挙動を示す**。JSON にすらならない。これは検証した 4 モデル全てで一貫
- **JSON 形式が返る・スキーマに準拠する**ためには、プロンプト本文で形式を文章指示する必要がある（API パラメータでは実現できない）
- RubyLLM 側は OpenAI 仕様準拠の payload を送っており、互換性ギャップは さくら側に固有
- RubyLLM の `chat.rb:172-178` には JSON.parse 失敗時のサイレントフォールバックがあり、`response.content` が `String` のままでも例外も警告も出ない
- **必須対策**: Sakura では `with_schema` / `response_format` を「スキーマ強制機構」として信頼してはならない。プロンプト内で出力形式を明示し、戻り値については呼び出し側で `Hash` 化と値レベル検証（型・enum・required）を必ず実施する


---

## 5. D: Tools / Function Calling

### 5.1 公式・抽象化レベル

| 項目 | 状況 |
|---|---|
| 公式マニュアル本文（操作ガイド・基本情報） | ❌ 記載なし |
| OpenAPI 仕様 | ✅ `tools`、`tool_choice`（none/auto/required/named）定義あり |
| Playground | ❌ 「Function Call などの機能は利用できません」と明示（S4） |
| API 受理 | モデル別（後述） |
| RubyLLM `with_tool` / `RubyLLM::Tool` | ✅ 既定 `tool_choice: auto` で multi-turn 自動実行 |

### 5.2 モデル × 実機 enforcement

| モデル | `tool_choice: auto` | `tool_choice: required` | `tool_choice: named` | `tool_choice: none` | 備考 |
|---|---|---|---|---|---|
| `gpt-oss-120b` | ✅ | ✅ | ✅ | ⚠️ 無視される（call が出る） | RubyLLM 既定の `auto` で問題なし |
| `llm-jp-3.1-8x13b-instruct4` | ❌ HTTP 400 `"auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser` | ✅ | ✅ | ⚠️ 自然文応答（call なし） | **RubyLLM 既定の `auto` だと BadRequestError**。`required`/`named` を使うか別 chat で対応 |
| `Qwen3-Coder-30B-A3B-Instruct` | ✅ | ✅ | ✅ | ⚠️ **content に `<tool_call>...</tool_call>` 形式の生 XML が漏洩** | tool 経由ではないが内部表現が露出 |
| `preview/Phi-4-mini-instruct-cpu` | ❌ HTTP 400 同上の vLLM エラー | ❌ HTTP 500 `Upstream server error` | ❌ HTTP 500 `Upstream server error` | ⚠️ HTTP 500 `Internal Server Error`（前回 200 で自然文。再現性に揺らぎあり） | **tools パラメータを送ると不安定。tool 利用は事実上不可** |

### 5.3 重要発見

- vLLM の起動オプション（`--enable-auto-tool-choice` 等）が **モデルごとに異なる構成**で配備されている
- `gpt-oss-120b` と `Qwen3-Coder-30B-A3B-Instruct` は tools 利用に堪える
- `llm-jp` は `tool_choice: required` または `named` に限定すれば使える
- `preview/Phi-4-mini-instruct-cpu` は tools パラメータを渡すと `auto` で HTTP 400、`required`/`named` で HTTP 500 を返し、tool 利用想定なし。同じプロンプトを `tools` 抜きで投げれば 200 で応答する
- RubyLLM のエラーメッセージは `RubyLLM::BadRequestError` として上層に出るので、原因（vLLM の起動オプション）は HTTP body 経由でのみ判明
- `Qwen3-Coder-30B-A3B-Instruct` で `tool_choice: none` 時に **`<tool_call>` 内部表現が `content` に漏れる**（推論エンジン側で Qwen の tool 表現の整形と `tool_choice: none` の解釈が未実装のように見える、記事化に値する挙動）

---

## 6. E: Streaming

| 項目 | 状況 |
|---|---|
| 公式 docs（OpenAPI） | ✅ `stream: boolean` 定義 |
| API 受理 | ✅ |
| RubyLLM `chat.ask { |chunk| ... }` | ✅ |
| 構造化出力 + streaming | ✅ 動く（chunks=99 → 最終 Hash） |
| `stream_options.include_usage: true` 強制（RubyLLM の挙動） | ✅ さくら側で問題なく受理 |
| **include_usage を付けない場合の挙動** | ☑️ Sakura は **既定で usage chunk を送ってくる**（include_usage の指定有無に関わらず） |

### 重要発見

- Phase 4 で懸念された「RubyLLM の `stream_options.include_usage: true` 強制が Sakura で 400 になる」は **実機では発生しない**
- 構造化出力 + streaming の組み合わせは（§4 のとおり schema 強制が効かない件はあるが）動作自体は完結する

---

## 7. F: Vision

### 7.1 公式・抽象化レベル

| 項目 | 状況 |
|---|---|
| OpenAPI 仕様 | ✅ `image_url` パート定義 |
| **画像 URL 形式の制約** | ⚠️ OpenAPI は `data:image/...;base64,...` の base64 data URI **限定記述**（外部 URL は未明示）|
| 対応モデルの公式マッピング | ❌ 公式に存在しない |
| RubyLLM `with: path` | ✅ |

### 7.2 モデル × 実機検証

検証画像: 外部 URL = `https://www.python.org/static/img/python-logo.png`、base64 = `tmp/images/sample.png`（リポジトリにコミット済の 48×48 PNG。元ソースは Debian の `/usr/share/pixmaps/debian-logo.png`）

| モデル | 外部 HTTPS URL | base64 data URI（48x48 PNG）|
|---|---|---|
| `preview/Qwen3-VL-30B-A3B-Instruct` | ✅ "Pythonのロゴです。" | ✅ "デビアンのロゴです。" |
| `preview/Phi-4-multimodal-instruct` | ✅ "Pythonのロゴ..." | ⚠️ "スパイラルが描かれています"（**誤認**） |

### 7.3 重要発見

- **OpenAPI は base64 限定の記述だが、実機では外部 HTTPS URL も受理される**（隠れ機能）
- 画像認識精度はモデル差大。Qwen3-VL は小画像でも判別可能、Phi-4-multimodal は同条件で誤認
- preview モデル 2 種ともに 200 を返すため、API 受理性だけでは判別できない

---

## 8. H: 基本パラメータの実機受理性

OpenAPI 未定義のパラメータを `gpt-oss-120b` に送付した結果（`tmp/probe_results/h_params__gpt-oss-120b.json`）:

| パラメータ | API 受理 | 実機 enforcement |
|---|---|---|
| `seed` | ✅ 200 | ⚠️ 検証中に reasoning_content 枯渇で content=null。再現性確定は別検証要 |
| `top_p` | ✅ 200 | 未確認 |
| `n: 2` | ✅ 200 | ❌ **choices=1 のみ返る**（n は無視される） |
| `stop: ['5']` | ✅ 200 | 未確認 |
| `presence_penalty` | ✅ 200 | 未確認 |
| `frequency_penalty` | ✅ 200 | 未確認 |
| `logprobs: true` | ✅ 200 | 未確認（`logprobs` フィールドは null 返り） |
| `user` | ✅ 200 | — |
| `definitely_unknown_param`（架空） | ✅ 200 | — 未知パラメータも受理される |

### 重要発見

- **OpenAPI 未定義パラメータも全て 200 で受理される**（黙って無視）
- `n` は典型的な「200 が返るが効果なし」例
- 「200 が返る ≠ パラメータが効いている」が普遍的に成立。**受理性と効果性は別軸で検証必要**

---

## 9. reasoning モデル特有の注意（gpt-oss-120b）

`gpt-oss-120b` は **reasoning モデル** であり、応答に `reasoning_content` フィールドが含まれる:

```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": null,
      "reasoning_content": "User wants random number 0-9 printed. Should generate ..."
    },
    "finish_reason": "length"
  }],
  "usage": { "completion_tokens": 16, ... }
}
```

> **注**: 上記 JSON は実機ログ `tmp/probe_results/a_connect__gpt-oss-120b.json`（`completion_tokens: 16`）を整形した例。`g_errors__gpt-oss-120b.json` の `huge_max_tokens` シナリオでは `completion_tokens: 35`。`content: null` + `reasoning_content` + `finish_reason: "length"` の構造は複数 probe で再現済。

| 観察 | 影響 |
|---|---|
| **`max_tokens` が小さいと `reasoning_content` だけで使い切られて `content` が `null`** | raw HTTP で content だけ見ていると原因不明な空応答に見える |
| `reasoning_content` は OpenAPI に未定義 | 仕様外のフィールド |
| RubyLLM は `extract_thinking_text` (`openai/chat.rb:165-168`) で `reasoning_content` / `reasoning` / `thinking` の優先順で吸収 | RubyLLM 経由なら `Message#thinking` で取れる |

### 推奨

- reasoning モデルでは `max_tokens` を最低でも数百以上に設定する
- raw HTTP 利用時は `reasoning_content` の存在を前提にパースを書く

---

## 10. RubyLLM 設定チェックリスト（Sakura 用）

検証で確定した必須／推奨設定:

```ruby
RubyLLM.configure do |c|
  c.openai_api_key  = ENV.fetch('SAKURA_AI_ACCOUNT_KEY')
  c.openai_api_base = 'https://api.ai.sakura.ad.jp/v1'  # ← /v1 まで含む
  # 旧来の system ロール送出に固定したい場合のみ次行を追加（既定は OpenAI reasoning モデル仕様準拠で developer 送出）
  # c.openai_use_system_role = true
end

chat = RubyLLM.chat(
  model: 'gpt-oss-120b',
  provider: :openai,            # ← 必須: モデル ID 衝突回避
  assume_model_exists: true     # ← 必須: registry 未登録回避
)
```

| 設定 | 必須/推奨 | 理由 |
|---|---|---|
| `openai_api_base` 末尾の `/v1` | 必須 | Faraday URL 結合の挙動。`/v1` を抜くと `/chat/completions` を直叩きしてしまう |
| `provider: :openai` | 必須 | RubyLLM models registry 内に同名モデル ID（azure/bedrock/openrouter 配下）が存在し、未指定だと意図しない provider が解決される |
| `assume_model_exists: true` | 必須 | Sakura 提供モデルは registry 未登録のため `ModelNotFoundError` を回避 |
| `openai_use_system_role: true` | 任意 | RubyLLM 既定では system メッセージが `developer` ロールとして送出される（OpenAI の o1 / GPT-5 系 reasoning モデル仕様に準拠）。Sakura 公式 OpenAPI でも `developer` は許容 enum として定義されており、probe `a_connect` で `gpt-oss-120b` 上で system / developer 双方が同一の prompt_tokens 数（90）で 200 受理されることを確認済み（[sakura-openapi-vs-openai-compatibility.md §1](sakura-openapi-vs-openai-compatibility.md)）。reasoning モデル以前の旧 `system` ロール挙動に固定したい場合や、`developer` を受け付けない OpenAI 互換サーバを併用する場合のみ明示する。検証範囲は `gpt-oss-120b` のみで、他モデルは vLLM の chat template 依存で扱いが異なる可能性あり |

---

## 11. plan.md §5.1 マトリクス（モデル × 機能 概観）

| | A 接続 | B model | C schema | D tools | E stream | F vision | G error | H その他 |
|---|---|---|---|---|---|---|---|---|
| `gpt-oss-120b` | ✅ | ✅ | ❌ schema強制なし | ✅ | ✅ | — | ✅ | ⚠️ |
| `llm-jp-3.1-8x13b-instruct4` | ↑ | ✅ | ❌ schema強制なし | ⚠️ auto不可 | ↑ | — | ↑ | ↑ |
| `Qwen3-Coder-30B-A3B-Instruct` | ↑ | ✅ | ❌ schema強制なし | ⚠️ none漏洩 | ↑ | — | ↑ | ↑ |
| `Qwen3-Coder-480B-A35B-Instruct-FP8` | ↑ | ✅ | 未検証（30B で代表） | ↑ | ↑ | — | ↑ | ↑ |
| `preview/Phi-4-mini-instruct-cpu` | ↑ | ✅ | ❌ schema強制なし | ❌ ほぼ全不可 | ↑ | — | ↑ | ↑ |
| `preview/Qwen3-VL-30B-A3B-Instruct` | ↑ | ✅ | 未検証 | 未検証 | ↑ | ✅ | ↑ | ↑ |
| `preview/Phi-4-multimodal-instruct` | ↑ | ✅ | 未検証 | 未検証 | ↑ | ⚠️ 小画像誤認 | ↑ | ↑ |

凡例: ✅=動く / ⚠️=動くが要注意 / ❌=動かない / ↑=代表モデル結果を継承（plan.md §3.5.3 戦略）

---

## 12. 時点性と再確認の推奨

- 本マトリクスは **2026-05-09** の調査結果。さくら側のモデル更新・vLLM 設定変更で挙動が変わる可能性が高い
- 特に preview/ モデルは予告なく終了/置換される可能性（公式は SLA 明示なし）
- 半年〜1 年後の再検証を推奨。`bin/probe` を再実行することで最小工数で再検証可能

---

## 13. 検証済 / 未検証の境界

### 検証済

- A, B, E, G, H: `gpt-oss-120b` で網羅検証済
- C, D: `gpt-oss-120b`, `llm-jp-3.1-8x13b-instruct4`, `Qwen3-Coder-30B-A3B-Instruct`, `preview/Phi-4-mini-instruct-cpu` で実機検証済
- F: `preview/Qwen3-VL-30B-A3B-Instruct`, `preview/Phi-4-multimodal-instruct` で実機検証済

### 未検証（必要なら追加）

- C / D の `Qwen3-Coder-480B-A35B-Instruct-FP8` での横展開（30B で代表取れると判断、無償枠抑制）
- C / D の preview vision モデルでの挙動（vision モデルがどこまでテキスト機能をサポートするか）
- H の seed / top_p の効果性確定（reasoning_content 枯渇により content=null になり計測できなかった）
- E のレート制限到達時の挙動（無償枠 3000 req/月の境界での挙動）
- 同時接続数の上限・タイムアウトの実値
- embeddings、audio transcription、TTS（plan.md §2 でスコープ外）
