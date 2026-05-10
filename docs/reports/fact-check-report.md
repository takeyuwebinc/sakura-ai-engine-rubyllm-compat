# ファクトチェック報告書

- 検証実施日: 2026-05-09
- 検証対象: `docs/reports/compatibility-matrix.md`, `docs/reports/troubleshooting.md`
- 一次ソース:
  - `docs/research/01-sakura-official.md`
  - `docs/research/02-rubyllm-internals.md`
  - `tmp/probe_results/*.json`（実機ログ、recorded_at: 2026-05-09T18:38〜18:50+09:00）
  - ローカル gem `ruby_llm-1.15.0`（`/home/yuichi/.rbenv/versions/4.0.2/lib/ruby/gems/4.0.0/gems/ruby_llm-1.15.0/lib/ruby_llm/`）

## サマリ

- 検証した主張の総数: 約 60 件（互換性マトリクスのセル + TS 各項目の load-bearing な主張）
- 一次ソースで裏付け確認できた: 約 53 件
- 修正が必要: 4 件（重要 1 / 中程度 3）
- 注意（軽微）: 4 件

## 検出した問題（優先度順）

### 🔴 重要（事実誤認・修正必須）

#### 問題 1: `preview/Phi-4-mini-instruct-cpu` の `tool_choice: required`/`named` が「vLLM エラー」と断定されているが probe ログでは未確認

> **2026-05-09 追記: 解決済み**。probe バグ（`d_tools.rb:113` の nil 参照）を修正し再実行した結果、`required: HTTP 500 / named: HTTP 500 / none: HTTP 500` を確実に記録（`d_tools__preview_Phi-4-mini-instruct-cpu.json` の `recorded_at: 2026-05-09T19:04:56+09:00`）。マトリクス §5.2 / §5.3 と TS-07 は実機データに基づき「auto: 400 / required・named: 500 / tools 自体が不安定」と書き換え済み。

- **対象**:
  - `compatibility-matrix.md` §5.2 表（行 132 セル）「`preview/Phi-4-mini-instruct-cpu` … `tool_choice: required` ❌ 同上 / `tool_choice: named` ❌ 同上」
  - `compatibility-matrix.md` §5.3 重要発見「`preview/Phi-4-mini-instruct-cpu` は tool 利用想定なし」
  - `troubleshooting.md` TS-07「`preview/Phi-4-mini-instruct-cpu` は `required` でも vLLM エラーになるため、tool 利用は事実上不可」
- **記述**: 「同上の vLLM エラー」「`required` でも vLLM エラーになる」
- **問題**: probe ログ `tmp/probe_results/d_tools__preview_Phi-4-mini-instruct-cpu.json` の `raw_tools_required` および `raw_tools_named` シナリオは **`NoMethodError: undefined method '[]' for nil`** で終わっており、これは `lib/probes/d_tools.rb:113` の `summarize` メソッドの実装バグ（`msg` が nil のときの nil チェック漏れ）に起因する。実機 HTTP 応答の生 body は probe バグにより取得失敗しており、`required`/`named` で 4xx が返ったかは **probe ログから確認不能**。
  - 唯一の vLLM エラー証拠は `rubyllm_with_tool` シナリオ（既定 `auto`）の `RubyLLM::BadRequestError: "auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser to be set` のみ。これは `auto` での挙動であり、`required`/`named` での挙動を示さない。
- **一次ソースが示す事実**: probe ログは `raw_tools_none` のみが完走しており、`required`/`named` は **未検証**。
- **推奨修正**:
  - 互換性マトリクス §5.2 の `preview/Phi-4-mini-instruct-cpu` 行の `required`/`named` セルを `❌ 同上` から `未検証（probe バグ）` に変更
  - §5.3 重要発見と TS-07 の「`required` でも vLLM エラーになる」を「`auto` で vLLM エラー。`required`/`named` は未検証だが同様に起動オプション側の制約を受ける可能性が高い」と推測扱いに緩める
  - もしくは probe バグ修正後に再実行して確定させる

### 🟡 中程度（要再確認・要追記）

#### 問題 2: 互換性マトリクス §3「公式表記揺れの解決」表に出典の不整合がある

- **対象**: `compatibility-matrix.md` §3.3 表（行 68-75）
- **記述**: 「`Qwen3-VL-30B-A3B-Instruct`（S6）」「`Phi-4-multimodal-instruct`（S6）」
- **問題**: research メモ §2.1 の S6 ライセンス表には `Qwen3-VL-30B-A3B-Instruct` と `Phi-4-multimodal-instruct` の記載がある（確認済）が、`Phi-4-mini-instruct`（S6）と `Qwen3-0.6B`（S6）は research §2.1 の S6 一覧に **`Phi-4-mini-instruct`** と **`Qwen3-0.6B`** として記載があり一致する。問題なし。ただし出典として「（S6）」とだけ書かれており、S5（操作ガイド）に同じモデル名が出てくるかは research §2.2 では「`gpt-oss-120b` / `llm-jp-3.1-8x13b-instruct4` / `Qwen3-Coder-...` のみ」と記載があり、Phi-4 系・Qwen3-0.6B・Qwen3-VL 系は **S6 にのみ** 記載という認識で正しい。これは軽微なので出典が S6 だけで OK。
- **一次ソースが示す事実**: research §2.1 / §2.2 と整合。
- **推奨修正**: 修正不要。再検証の結果として「整合」と判定。**この項目は問題なしに格下げ**。（注: 当初疑念を持ったが裏付け確認できた）

#### 問題 3: TS-13 のソース行番号引用 `openai/chat.rb:21, 49` のうち `21` 行目は引用意図がやや誤誘導

- **対象**: `troubleshooting.md` TS-13「`openai/chat.rb:21, 49`」
- **記述**: 「RubyLLM は `stream_options: { include_usage: true }` を **常時** 付与する（`openai/chat.rb:21, 49`）」
- **問題**: 実機 gem `ruby_llm-1.15.0` の `openai/chat.rb:21` は `stream: stream` の代入行（payload に `stream` 真偽値を入れる箇所）であり、`stream_options: { include_usage: true }` の付与は **49 行目のみ**。`21` を併記すると「21 行目に include_usage がある」と誤読される可能性。
- **一次ソースが示す事実**: 49 行目「`payload[:stream_options] = { include_usage: true } if stream`」のみが該当。`21` は `stream` キー設定行（前後文脈を示す意図と思われる）。
- **推奨修正**: `(openai/chat.rb:49、stream フラグ自体は :21)` のように分けて書くか、`(openai/chat.rb:49)` のみに簡略化。research メモ 02 §2.1 でも同じ表記が踏襲されている。

#### 問題 4: 互換性マトリクス §7.2 の base64 検証画像のソース表記と probe 実装が不一致

- **対象**: `compatibility-matrix.md` §7.2 行 176「base64 = `/usr/share/pixmaps/debian-logo.png`（48x48 PNG）」
- **記述**: base64 ソース画像が `/usr/share/pixmaps/debian-logo.png`
- **問題**: probe 実装 `lib/probes/f_vision.rb:12` では `LOCAL_IMAGE_PATH = File.expand_path('../../tmp/images/sample.png', __dir__)` を使用しており、`/usr/share/pixmaps/debian-logo.png` を直接参照していない。`tmp/images/sample.png` は確かに 48×48 PNG（`file` コマンドで確認）で、認識結果が「デビアンのロゴです。」「スパイラルが描かれています」となっており Debian ロゴの可能性が高いが、**マトリクスの記述を読んだ第三者が再現する際に `/usr/share/pixmaps/debian-logo.png` を直接読み込もうとして食い違う可能性**がある。
- **一次ソースが示す事実**: probe 実装は `tmp/images/sample.png`（リポジトリ内画像）を使う。`/usr/share/pixmaps/debian-logo.png` は **元ソースとして使われた可能性が高いがコミットされた画像とは別実体**。
- **推奨修正**: 「base64 = `tmp/images/sample.png`（48x48 PNG、Debian ロゴ）」と probe 実装に合わせて表記する、もしくは「Debian ロゴ 48x48 PNG（`tmp/images/sample.png` にコミット済）」とする。

### 🟢 軽微（用語ゆらぎ・タイポ等）

#### 問題 5: 互換性マトリクス §9 の reasoning モデル応答サンプル JSON の数値が実機ログと一致しない

- **対象**: `compatibility-matrix.md` §9 行 220-231 の JSON 例「`"completion_tokens": 32`」
- **問題**: 実機ログ `a_connect__gpt-oss-120b.json` では `completion_tokens: 16`、`g_errors__gpt-oss-120b.json` の `huge_max_tokens` シナリオでは `35`。`32` という数値は **どの probe ログとも一致しない**。
- **影響**: 構造（`content: null` + `reasoning_content` + `finish_reason: "length"`）は probe ログで再現されているため、概念例として誤りはない。ただし「実機ログから抜粋」と読まれると不正確。
- **推奨修正**: コメントとして「（数値は説明用の合成例。実 probe ログは `a_connect__gpt-oss-120b.json` 参照）」を追加するか、実機ログそのままの値に書き換える。

#### 問題 6: TS-20 の Python 言及が誇張気味

- **対象**: `troubleshooting.md` TS-20「公式 Zenn 記事のサンプルは Python `OPENAI_API_KEY` を使うが」
- **問題**: research §6.4 (Z6) で言及されているのは個人記事 `qwen-code` 系の `OPENAI_BASE_URL` / `OPENAI_MODEL` 設定であり、`OPENAI_API_KEY` は明示出典の `~/.qwen/.env` 上の言及（個人記事 Z6）。**「公式 Zenn」と断定するのは出典強度がやや過剰**。Z2/Z3 は `client_args["api_key"]` に直接渡すサンプル。
- **推奨修正**: 「公式 / 個人 Zenn 記事のサンプルは Python の `OPENAI_API_KEY` 等を使う傾向だが」のように出典範囲をぼかす。

#### 問題 7: TS-12 の表「401 = Unauthorized / Invalid token の差で原因切り分け」の表構造が崩れている

- **対象**: `troubleshooting.md` TS-12 行 222-225
- **問題**: マークダウン表の最終行「| 401 = `Unauthorized`（ヘッダ無し）/ `Invalid token`（ヘッダはあるが値が NG）の差で原因切り分け |」が **「対処」列のみで「原因」列が空** になっており、表として不正。区切り線記法では 2 列だが 1 列分しか書かれていない。
- **推奨修正**: 「| メッセージで原因切り分け | 401 = `Unauthorized`（ヘッダ無し）/ `Invalid token`（ヘッダはあるが値が NG） |」のように 2 列に分割する。

#### 問題 8: 互換性マトリクス §11 の `Qwen3-Coder-480B-A35B-Instruct-FP8` 行で「同上」記号の使い方に曖昧さ

- **対象**: `compatibility-matrix.md` §11 表 280 行「Qwen3-Coder-480B…」の D 列「同上」
- **問題**: `D tools` 列に「同上」とあるが、直前モデルは `Qwen3-Coder-30B-A3B-Instruct`（D=⚠️ none漏洩）。「30B 結果を継承」と読むのが文脈的に自然だが、§11 凡例では `↑=代表モデル結果を継承` と書かれている一方、ここだけ「同上」と書いている表記ブレ。
- **推奨修正**: `↑` に統一する。

---

## 検証済（裏付け確認できた主張のサンプル）

代表的な確認済主張を出典付きで列挙する。

1. **`/v1/models` で取得した実 API モデル文字列 11 個**（`gpt-oss-120b`, `llm-jp-3.1-8x13b-instruct4`, `Qwen3-Coder-30B-A3B-Instruct`, `Qwen3-Coder-480B-A35B-Instruct-FP8`, `preview/Qwen3-0.6B-cpu`, `preview/Phi-4-mini-instruct-cpu`, `preview/Qwen3-VL-30B-A3B-Instruct`, `preview/Phi-4-multimodal-instruct`, `preview/Qwen3-Embedding-4B-FP16`, `multilingual-e5-large`, `whisper-large-v3-turbo`）→ `tmp/probe_results/v1_models.json` および `b_models__all.json` で完全一致確認

2. **公式表記との差分（`Phi-4` / `Phi-4-mini-instruct` / `Phi-4-multimodal-instruct` / `Qwen3-VL-30B-A3B-Instruct` / `Qwen3-0.6B` / `Kimi-K2.5` のいずれも 400 `"This model is not available."`）** → `b_models__all.json` の `per_model` で全件確認

3. **`gpt-oss-120b` の構造化出力で `condition: "partly cloudy"` という enum 違反値が返る** → `c_schema__gpt-oss-120b.json` の全シナリオで再現

4. **`llm-jp-3.1-8x13b-instruct4` で `with_schema` 指定時に String の長文自然文が返る（サイレント失敗）** → `c_schema__llm-jp-3.1-8x13b-instruct4.json` の `rubyllm_with_schema` で `content_class: "String"`, `raw_string_indicates_silent_failure: true`

5. **`preview/Phi-4-mini-instruct-cpu` で Markdown コードブロック付き JSON が返る** → `c_schema__preview_Phi-4-mini-instruct-cpu.json` の `content_head: "```json\\n\\n{...}\\n\\n```"`

6. **`llm-jp-3.1-8x13b-instruct4` の RubyLLM `with_tool` (auto) が `BadRequestError: "auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser to be set` で落ちる** → `d_tools__llm-jp-3.1-8x13b-instruct4.json` の `rubyllm_with_tool` で再現

7. **`Qwen3-Coder-30B-A3B-Instruct` の `tool_choice: 'none'` で content に `<tool_call>...</tool_call>` の生 XML が漏れる** → `d_tools__Qwen3-Coder-30B-A3B-Instruct.json` の `raw_tools_none` で再現

8. **`gpt-oss-120b` の `tool_choice: 'none'` が無視されて `finish_reason: tool_calls` が返る** → `d_tools__gpt-oss-120b.json` の `raw_tools_none` で確認

9. **streaming で `include_usage` 指定有無に関わらず usage chunk が返る** → `e_streaming__gpt-oss-120b.json` の `raw_stream_no_usage` で `usage_chunk_seen: true`

10. **vision 実機: Qwen3-VL は外部 URL/base64 とも認識成功、Phi-4-multimodal は 48×48 PNG で「スパイラル」と誤認** → `f_vision__preview_Qwen3-VL-30B-A3B-Instruct.json` および `f_vision__preview_Phi-4-multimodal-instruct.json`

11. **`temperature: 99.9` および `max_tokens: 10_000_000` が 200 で受理される** → `g_errors__gpt-oss-120b.json` の `invalid_temperature` / `huge_max_tokens`

12. **`n: 2` 送付しても `choices` が 1 件のみ** → `h_params__gpt-oss-120b.json` の `n_2` シナリオで `choice_count: 1`

13. **OpenAPI 未定義パラメータ（`seed`, `top_p`, `presence_penalty`, `frequency_penalty`, `logprobs`, `user`, `definitely_unknown_param` 等）が全て 200 で受理** → `h_params__gpt-oss-120b.json` で確認

14. **401 認証エラーは `{"error":{"message":"Unauthorized"}}` または `{"error":{"message":"Invalid token"}}` の形** → `g_errors__gpt-oss-120b.json` で確認

15. **`developer` ロール送付時も 200** → `a_connect__gpt-oss-120b.json` の `raw_with_developer`

16. **RubyLLM ソース行番号の正確性**:
    - `chat.rb:172-178` の構造化出力サイレントフォールバック（TS-04, §4.3）→ ローカル gem で完全一致
    - `openai/chat.rb:165-168` の `extract_thinking_text`（§9, TS-06）→ 一致
    - `openai/chat.rb:135-142` の `format_role`（TS-15）→ 一致
    - `connection.rb:102-114` の `retry_exceptions`（TS-12）→ 一致、401 は含まれない
    - `configuration.rb:46` の `request_timeout: 300`（TS-18）→ 一致
    - `tools.rb:73-101` の `parse_tool_call_arguments` / `parse_tool_calls`（TS-14）→ 一致、JSON.parse の rescue 無し確認

17. **公式 OpenAPI に `response_format` / `json_schema` 定義なし**（§4, TS-04, TS-05）→ research §3.4 / §5 で確認

18. **公式 OpenAPI が `image_url` を base64 data URI 限定で記述**（§7, TS-16）→ research §3.5 で確認

19. **`/v1/models` 相当のモデル一覧取得 API が OpenAPI に定義なし**（§2 B', TS-03）→ research §3 / §5 / §7 で確認

20. **Sakura 無償枠 chat completions 3,000 req/月**（TS-17）→ research §4.2 で確認（出典 S12, S13）

21. **`Configuration#default_model` が `'gpt-5.4'`**（research §6.4 言及 / §10 関連）→ ローカル gem `configuration.rb:35` で確認

22. **Playground は Function Call 不可（S4）**（§5.1）→ research §3.3 / §5 で確認

---

## 補足: 検証範囲外として明示しておくべき点

- 互換性マトリクス §10 の「`/v1` を抜くと `/chat/completions` を直叩きしてしまう」は **実機未検証**。research §1.1 の Faraday URL 結合に関する考察に基づく推測。実機で再現する probe を追加すると確実性が上がる。
- 互換性マトリクス §11 の `preview/Qwen3-VL-30B-A3B-Instruct` および `preview/Phi-4-multimodal-instruct` の C/D 列が「未検証」のまま留まっている点は誠実な表記で問題なし。
- TS-17 の「無償プランで連続呼出するうちに 429 が返るようになる」「具体値は公式記載なし」は probe ログで実機到達検証はされていない。research §4.7 で「具体値は公式記載なし」と明示されておりラベル付けは妥当。
