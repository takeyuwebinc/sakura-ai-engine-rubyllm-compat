# 横断整合性チェック報告書

- 検証実施日: 2026-05-09
- 検証対象:
  - `docs/reports/compatibility-matrix.md`（互換性マトリクス、以下「Matrix」）
  - `docs/reports/troubleshooting.md`（トラブルシューティング集 TS-01〜TS-20、以下「TS」）
  - `docs/article/draft.md`（技術記事ドラフト、以下「Draft」）
- 補助ソース:
  - `docs/research/01-sakura-official.md`, `docs/research/02-rubyllm-internals.md`
  - `tmp/probe_results/*.json`（実機ログ）
  - `docs/reports/fact-check-report.md`（先行ファクトチェック）

---

## サマリ

- 文書間矛盾: **2 件**（重要 1 / 軽微 1）
- 用語ゆらぎ: **3 件**
- 推奨修正: **5 件**（重要 1 / 中程度 2 / 軽微 2）
- 整合確認できた重点項目: 22 件

3 文書の事実関係・モデル名・推奨設定・コード例は **おおむね高い整合性**を保っている。重大な事実の食い違いは 1 件のみ（Draft §6.4 の章ラベルと内容の齟齬）。残りはコメントの粒度差、文言ゆれ、出典記述の有無など軽微な差異に留まる。

なお `fact-check-report.md` で「重要」とされていた **Phi-4-mini の `tool_choice: required/named` が probe バグで未検証**という指摘は、最新 probe ログ（`d_tools__preview_Phi-4-mini-instruct-cpu.json`、`recorded_at: 2026-05-09T19:04:56+09:00`）で `required: HTTP 500 / named: HTTP 500` が記録されており **既に解消済み**。3 文書の HTTP 500 確定記述は probe ログと整合する。

---

## 検出した矛盾（優先度順）

### 🔴 重要（事実が文書間で矛盾）

#### M-01: Draft §6.4 の章タイトル「**GA 小型系**」が本文・他文書と矛盾

- **対象**: `docs/article/draft.md` 行 312
- **記述**: 「### 6.4 GA 小型系: `preview/Phi-4-mini-instruct-cpu`」
- **矛盾相手**:
  - 同 §6.4 本文（行 314）「Microsoft Phi-4-mini-instruct を **CPU で動かす preview モデル**です」
  - 同 §2 結論先出しマトリクス（行 43）`preview/Phi-4-mini-instruct-cpu` は `preview/` プレフィックス付き
  - Matrix §3.1 表「区分: preview」（行 54）
  - Matrix §11 概観表でも `preview/Phi-4-mini-instruct-cpu` 行（行 283）
  - TS-19「preview/ モデルが急に消えた」の対象に該当
- **真偽判定**: probe ログ `tmp/probe_results/v1_models.json` で `id: "preview/Phi-4-mini-instruct-cpu"` と確定。**preview が正しい**。
- **推奨修正**: Draft §6.4 の章タイトルを **「6.4 preview 小型系: `preview/Phi-4-mini-instruct-cpu`」** に変更する。「GA 小型系」は誤り。
  - 同様に §6.1〜§6.3 が「6.1 GA テキスト系」「6.2 GA 日本語系」「6.3 GA コード系」と全て GA カテゴリで命名されているため、§6.4 だけ preview なのに GA 表記なのは編集ミスと推測される。

### 🟡 中程度（用語ゆらぎ、説明の粒度差）

#### M-02: Phi-4-mini の `tool_choice: none` の「再現性揺らぎ」言及の有無が 3 文書で粒度差

- **対象**:
  - Matrix §5.2 行 132: `none` セルに「⚠️ HTTP 500 `Internal Server Error`（前回 200 で自然文。再現性に揺らぎあり）」と明記
  - Draft §6.4 表（行 334): 「HTTP 500 `Internal Server Error`（同じプロンプトを 2 回叩いて 1 回は 200、再現性に揺らぎあり）」と明記
  - TS-07 末尾（行 155): 「`tools` パラメータを送ると挙動が不安定」の包括表現のみで、`none` 単独の再現性揺らぎは明記なし
- **真偽判定**: probe ログ `d_tools__preview_Phi-4-mini-instruct-cpu.json` の `raw_tools_none` は `status: 500`。揺らぎ自体は probe では再現していないが Matrix/Draft の脚注として残っている。
- **推奨修正**: TS-07 の最後の段落に「`none` についても probe では HTTP 500 だが、過去に 200 が返った観察例あり（再現性不安定）」と一行追記し、Matrix/Draft と粒度を揃える。または Matrix/Draft 側の「揺らぎあり」記述を probe ログに沿って削るかどちらか統一する。

#### M-03: `huge_max_tokens` 観察時の `completion_tokens` 数値が Matrix §9 と probe ログで一致

- **対象**: Matrix §9 の reasoning モデル応答 JSON 例（行 220-231）
- **記述**: `"completion_tokens": 32`
- **整合状況**: Matrix §9 直下の「注」（行 233）で「**説明用に整形した合成例**。実機ログは `a_connect__gpt-oss-120b.json`（completion_tokens=16）、`g_errors__gpt-oss-120b.json` の `huge_max_tokens` シナリオ（completion_tokens=35）を参照」と既に注記済み。
- **Draft §6.1**: 同じ JSON 例を掲載しているが `completion_tokens` フィールドそのものを含めていないため数値矛盾は発生していない。
- **TS-06**: 簡略化された JSON 例（行 124-133）でも `completion_tokens` フィールド自体を含めていない。
- **判定**: 現状の注釈で十分整合。修正不要。**ただし**、Matrix §9 の合成例の `completion_tokens` 値を実機ログと合わせて `16` または `35` に書き換えると、初見読者の混乱が完全に消える（任意改善）。

### 🟢 軽微（フォーマット・表記のみの差）

#### M-04: モデル区分名の表記揺れ

- 同じ `gpt-oss-120b` を指して:
  - Matrix §3.1: 「GA」
  - Draft §4.3 表: 「GA（reasoning）」
  - Draft §6.1: 「OpenAI が公開した gpt-oss-120b を vLLM で配備した、本サービスの代表モデル」
- 同じ `llm-jp-3.1-8x13b-instruct4` を指して:
  - Matrix §3.1: 「GA」
  - Draft §4.3 表: 「GA（日本語特化 MoE）」
- **判定**: Draft 側がより詳細な注釈を追加しているだけで矛盾ではない。修正不要。

#### M-05: `Phi-4-multimodal` の base64 誤認応答の引用文言

- Matrix §7.2 行 181: `"スパイラルが描かれています"`
- TS-16 行 289: 「`Debian ロゴ` を「スパイラル」と誤認」
- Draft §6.5 行 365: 「この画像にはスパイラルが描かれています。」
- **判定**: 抜粋粒度の差で意味は一致。修正不要。

#### M-06: 設定例のコメント表現の差

- Matrix §10 のコメント:
  - `# ← /v1 まで含む`
  - `# ← 必須: モデル ID 衝突回避`
  - `# ← 必須: registry 未登録回避`
- Draft §4.2 のコメント:
  - `# 末尾の /v1 を含める`
  - `# 必須`
  - `# 必須`
- **判定**: コードは完全に同等、コメント詳細度のみ差異。Draft は表で別途理由を解説しているため重複回避と読める。**修正不要**。
- **更新履歴**: 旧版は `c.openai_use_system_role = true` の `# 推奨: developer ロール送出を回避` / `# 推奨` の対比行を含んでいたが、当該設定が「任意」に格下げされた（[ChangeSpec 履歴](../change-specs/) の `relax-openai-use-system-role-recommendation.md`）ため、両ファイルから同設定行が削除され比較対象外となった。
- **Ruby 構文**: 両者とも Ruby 4.0.2 で valid。

---

## 用語ゆらぎ（参考メモ）

| 用語 | Matrix | TS | Draft | 統一案 |
|---|---|---|---|---|
| reasoning モデル | reasoning モデル | reasoning モデル | reasoning モデル | 統一済み |
| `tool_choice` の named | `named` | 「特定 tool 名」「named」混在 | 「特定 tool 名指定」「named」混在 | `named`（特定 tool 名）で統一推奨 |
| Sakura の base URL | `https://api.ai.sakura.ad.jp/v1` | 同上 | 同上 | 統一済み |
| 公式マニュアル参照記号 | S4/S5/S6/S12 | S6/S12 | S5/S6（一部） | 索引記号として統一済み |

---

## 整合確認できた主要項目

以下、3 文書間で完全に整合していることを確認した代表項目:

1. **モデル文字列の表記**: 8 チャットモデル全てで `preview/` プレフィックス、`-cpu` サフィックス、`-FP8` サフィックスの過不足なく一致
   - `gpt-oss-120b`、`llm-jp-3.1-8x13b-instruct4`、`Qwen3-Coder-30B-A3B-Instruct`、`Qwen3-Coder-480B-A35B-Instruct-FP8`、`preview/Qwen3-0.6B-cpu`、`preview/Phi-4-mini-instruct-cpu`、`preview/Qwen3-VL-30B-A3B-Instruct`、`preview/Phi-4-multimodal-instruct`

2. **C 構造化出力 × モデル挙動**:
   - `gpt-oss-120b` → `"partly cloudy"`（Matrix §4.2、TS-05、Draft §6.1 一致）
   - `llm-jp` → 自然文（Matrix §4.2、TS-04、Draft §6.2 一致）
   - `Qwen3-Coder-30B` → `"曇り"`（Matrix §4.2、TS-05、Draft §6.3 一致）
   - `Phi-4-mini` → Markdown ` ```json ... ``` `（Matrix §4.2、TS-04、Draft §6.4 一致）

3. **D Tools × モデル挙動**:
   - `gpt-oss-120b`: auto/required/named ✅、none 無視（Matrix §5.2、TS-08、Draft §6.1 一致）
   - `llm-jp`: auto は HTTP 400 vLLM エラー、required/named OK（Matrix §5.2、TS-07、Draft §6.2 一致）
   - `Qwen3-Coder-30B`: 全て OK、`none` で `<tool_call>` XML 漏洩（Matrix §5.2、TS-09、Draft §6.3 一致）
   - `Phi-4-mini`: auto = 400 / required = 500 / named = 500、tools 自体が不安定（Matrix §5.2、TS-07、Draft §6.4、§7 TS-07 全て一致）。fact-check 報告書の「probe バグで未検証」は **解決済み**

4. **F Vision × モデル挙動**:
   - Qwen3-VL: 外部 URL/base64 ともに正答（Matrix §7.2、TS-16、Draft §6.5 一致）
   - Phi-4-multimodal: 48×48 base64 で「スパイラル」と誤認（同上）

5. **`response_format` の HTTP 受理性**: 全モデルで 200 が返るが schema 強制されないという主張が 3 文書一致

6. **`/v1/models` API**: OpenAPI 未定義だが実装あり（Matrix §2 B'、TS-03、Draft §4.3 一致）

7. **公式マニュアル表記揺れ**: `Phi-4-mini-instruct` → `preview/Phi-4-mini-instruct-cpu` 等の表記差（Matrix §3.3、TS-03、Draft §4.3 一致）。`Kimi-K2.5` 未提供も Matrix §3.3、Draft §4.3 で一致言及

8. **RubyLLM 設定の必須/推奨 3 項目**: `provider: :openai`、`assume_model_exists: true`、`openai_api_base` 末尾 `/v1` の 3 項目が Matrix §10 と Draft §4.2 で一致。`openai_use_system_role` は実機検証と Sakura OpenAPI 仕様（`developer` 許容 enum）に基づき「任意」に格下げされ、整合性チェック対象から除外

9. **`max_retries` 既定値 3、`request_timeout` 既定 300 秒**: TS-17/TS-18、Draft §5.4 一致

10. **無償枠 3,000 req/月**: Matrix §13、TS-17、Draft §5.4 一致（出典は Sakura 公式 S12）

11. **TS 番号参照**: Draft §7 が引用する TS-04, TS-06, TS-07, TS-08, TS-09, TS-10, TS-11, TS-12, TS-15, TS-17, TS-19 は全て troubleshooting.md に存在し、内容も整合

12. **コード例の Ruby 構文**: Draft §4.2、§5.1、§6.1〜§6.5、§7、付録の全コードブロックが Ruby 4.0.2 構文として valid

13. **「未検証」「実機検証済」ラベルの一貫性**: Matrix §11 / §13 で「未検証」と明示された項目（preview vision の C/D 列、`Qwen3-Coder-480B` の C/D 横展開）は Draft §2 の凡例でも「未検証」と継承表記。TS は症状ベースなので「未検証」ラベル自体不要。整合

14. **RubyLLM ソース行番号引用**:
    - `chat.rb:172-178`（構造化出力サイレントフォールバック）: Matrix §4.3、TS-04、Draft §5.1 一致
    - `openai/chat.rb:165-168`（extract_thinking_text）: Matrix §9、TS-06、Draft §6.1 一致
    - `openai/chat.rb:135-142`（system role）: TS-15、Draft §4.2 ともに「`developer` 送出も Sakura OpenAPI で許容され、`gpt-oss-120b` 実機で system 送出と同等に受理される」方向で一致
    - `connection.rb:102-114`（リトライ）: TS-12、TS-17、Draft §5.4 一致
    - `tools.rb:73-101`（tool_call JSON parse 例外貫通）: TS-14、Draft §5.2 一致
    - `configuration.rb:46`（request_timeout 300）: TS-18 のみ（他文書では言及なし）

15. **OpenAPI 制約値非強制**: `temperature: 99.9`、`max_tokens: 10_000_000` が 200 受理（Matrix §2 G、TS-11、Draft §7 TS-11 一致）

---

## 補助ソースとの整合性

- `tmp/probe_results/v1_models.json`: 11 モデル（チャット 8 + embeddings 2 + audio 1）が 3 文書のモデル一覧と完全一致
- `tmp/probe_results/d_tools__preview_Phi-4-mini-instruct-cpu.json`: `auto: 400 / required: 500 / named: 500 / none: 500` を 3 文書全てが正しく反映
- `tmp/probe_results/c_schema__*.json`: 4 モデルの構造化出力挙動を 3 文書全てが正しく反映
- `tmp/probe_results/f_vision__*.json`: vision 認識結果を 3 文書全てが正しく反映
- `tmp/probe_results/h_params__gpt-oss-120b.json`: `n: 2` が無視される事実を Matrix §8、TS-10、Draft §7 TS-10 全てが反映

---

## 推奨アクション（優先度順）

1. **【重要】Draft §6.4 章タイトル修正**: 「6.4 GA 小型系」→「6.4 preview 小型系」（M-01）
2. **【中】TS-07 末尾の Phi-4-mini `none` シナリオに揺らぎ言及を追記、または Matrix/Draft 側の揺らぎ記述を probe ログに合わせる**（M-02）
3. **【任意】Matrix §9 の合成 JSON 例の `completion_tokens: 32` を `16` または `35`（実機ログ値）に書き換え**（M-03）
4. **【任意】用語「named」「特定 tool 名」の表記統一**（用語ゆらぎ）
5. **【任意】fact-check-report.md の問題 1（Phi-4-mini probe バグ）に「**2026-05-09 再 probe で解決済み**」の追記**（fact-check 自体の更新）
