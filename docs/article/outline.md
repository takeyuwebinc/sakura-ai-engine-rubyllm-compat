# 技術記事 アウトライン（Phase 2 確定版）

## メタ情報

- **タイトル候補**:
  1. **「OpenAI 互換」の境界線を引く — RubyLLM × さくらのAI Engine の API 互換性ガイド**（推奨, 約 49 字）
  2. RubyLLM で さくらのAI Engine を本番運用する前に知るべき API 互換性ギャップ（約 44 字）
  3. OpenAI 互換クライアントの先で何が変わるか — RubyLLM × さくらのAI Engine 検証（約 50 字）
- **採用タイトル**: 候補 1（境界線を引くというスタンスを明示し、RubyLLM × Sakura の組み合わせを検索キーワードとして含めた）
- **媒体**: Zenn
- **想定文字数**: 10,000〜13,000 字
- **記事タイプ**: トラブルシューティング + 比較・選定型のハイブリッド（解決策サマリー必要）

## Phase 1 確定事項

### 一番書きたいこと

さくらのAI Engine の「OpenAI 互換」は HTTP リクエストの受理性レベルでは成立するが、`tool_choice: none`/OpenAPI 数値制約の強制/エラー応答構造/`response_format` の 4 点で公式 OpenAI と異なる。さらに RubyLLM 1.15.0 側にも、registry 同名衝突・`with_schema` のサイレント String 化・429 自動リトライ等、互換クライアントに依存することで生まれる固有の罠がある。

### 記事のゴール

読者が以下を獲得する:

- 「OpenAI 互換」の何が保証されていて何が保証されていないかを HTTP / 推論エンジン / モデル の責務で切り分けられる
- RubyLLM で Sakura に向けるとき、どの分岐・バリデーション・リトライ抑止を実装の防御点として置くべきか具体的に決められる
- 互換性ギャップに遭遇したとき、Sakura OpenAPI 仕様と公式 OpenAI 仕様のどちらに従うべきかを判断できる

### ターゲット & 既知領域

**読者像**:

- Rails / RubyLLM 経験あり、OpenAI 互換 API（さくら、Groq、TogetherAI 等）の業務評価/採用検討中のエンジニア
- 公式 OpenAI で動いているコードを base_url 差し替えだけで動かしたい／動いている人
- LLM 推論エンジン（vLLM 等）の内部仕様には詳しくない

**既知領域（記事中で説明しない）**:

- Ruby/Rails 基本（Gemfile、bundle exec、ENV、dotenv、initializers）
- RubyLLM の基本 API（`RubyLLM.configure`、`RubyLLM.chat`、`chat.ask`、`chat.with_tool`、`chat.with_schema`、`Message#content`）
- HTTP / JSON / SSE の基本概念、HTTP ステータスコードの一般的な意味
- OpenAI Chat Completions API の基本パラメータ（`messages`、`role`、`temperature`、`max_tokens`、`tools`、`tool_choice`、`response_format`）と JSON Schema
- Bearer トークン認証、Authorization ヘッダ
- webmock / VCR 等の HTTP モックの存在

**説明が必要（記事中で必ず触れる）**:

- 「OpenAI 互換」の二段構え — 「同じクライアントで叩ける」レベルと「振る舞いが完全一致する」レベルの差
- Sakura 公式 OpenAPI 仕様の存在と、それが実機挙動の契約であるとは限らないこと
- RubyLLM の registry 解決順とサイレントフォールバックの存在
- 自動リトライの対象例外群（429 を含む）

## マクロ構造（h2 単位）

```
1. (タイトル)
2. (総論パラグラフ — 結論先出し 4 文)
3. 解決策サマリー — 安全に動かすための最小設定
4. 「OpenAI 互換」の二段構え — どこまでが互換か
5. Sakura が公式 OpenAI と異なる4箇所（非互換）
6. Sakura で気をつけるべき4つの差異（注意）
7. RubyLLM 側に潜む4つの罠
8. 本番投入前のチェックリスト
9. まとめ
10. 付録: 検証環境と参照
```

## 読者のメンタルモデル設計

### 読者の初期状態

- OpenAI Chat Completions API は使い慣れている
- 「OpenAI 互換」と書かれていれば base_url 差し替えで同じコードが動くと素朴に期待
- HTTP 200 が返れば成功、400 は入力ミス、429 はレート制限、と一対一で考えがち
- RubyLLM は内部的に「OpenAI 互換クライアント」として汎用的に使えると認識している

### 読者の動機設計（背景の代わり）

- **解決する痛み**:
  - Sakura に切り替えたら schema が効かない／tool_choice が効かない／なぜか課金が増える、といった原因不明な現象に遭遇する
  - 公式 OpenAI で組んだエラーハンドリングが Sakura で意図通りに分岐しない
  - 仕様書（Sakura OpenAPI）と実機の差にハマる
- **得られる状態**:
  - 互換性ギャップを「HTTP 契約の差」「RubyLLM の汎用化が招く差」の 2 軸で説明できる
  - 本番のバリデーション・エラー分岐・リトライ抑止を具体的なコード防御点として置ける
- **恩恵の提示位置**: §2 総論で「4 + 4 + 4 の互換性ギャップがある」と数字で先出し

### 導入する概念と依存関係

```
「OpenAI 互換」の二段構え（HTTP プロトコルレベル vs 振る舞い完全一致レベル）
  ↓ (前提)
Sakura OpenAPI 仕様の役割と限界
  ↓ (応用)
非互換4 × 注意4（§5, §6）
RubyLLM の registry / サイレントフォールバック / リトライポリシー（§7）
```

§4 で二段構えの概念を導入してから、§5〜§7 で各論を「これは契約レベルの差か、クライアント実装の差か」で紐付ける。

## h3 単位の見出し詳細

### §1 タイトル

(本文なし、メタ)

### §2 総論パラグラフ（4 文）

1. さくらのAI Engine の「OpenAI 互換」は HTTP リクエストの受理性レベルでは成立するが、振る舞いが公式 OpenAI と完全一致するわけではない
2. 検証可能な互換性ギャップは「Sakura が公式 OpenAI と異なる箇所」で 4 件の非互換と 4 件の注意点、加えて RubyLLM 1.15.0 を OpenAI 互換クライアントとして使う際の固有の罠が 4 件
3. これらは公式 OpenAI のエラーボディ前提の `error.code` 分岐、`response_format` を「型安全な構造化出力」と思って組まれた呼び出し、429 を例外で止めるつもりで組んだループのいずれをも壊す
4. 本記事は Sakura 公式 OpenAPI と公式 OpenAI 実機の比較、および RubyLLM 1.15.0 のソースコード分析を組み合わせ、本番投入前に置くべき防御点を具体的なコードで提示する

### §3 解決策サマリー — 安全に動かすための最小設定

- 必要十分な `RubyLLM.configure` ブロックと `chat` 呼び出し
  - `provider: :openai`, `assume_model_exists: true`（registry 衝突対策）
  - `c.openai_use_system_role = true`（developer ロール変換抑止）
  - `c.max_retries = 0`（429 自動再送による多重課金回避）
- 1 行注釈で各設定の理由を示し、詳細は該当節へ
- 「これで `gpt-oss-120b` への基本チャットは安全に動く。`with_schema` や tools の挙動差は本文を確認のこと」

### §4 「OpenAI 互換」の二段構え — どこまでが互換か

- §4.1 「同じ OpenAI 互換クライアントで叩ける」レベルは成立する
  - HTTP プロトコル / 認証、基本リクエスト、`tool_choice: auto/required`、vision 受理性、streaming 基本は公式 OpenAI と一致
- §4.2 「振る舞いが完全一致する」レベルは成立しない
  - 互換性のレイヤを HTTP / レスポンス構造 / 制約強制 / エラー応答 / クライアント実装 で切り分ける
- §4.3 Sakura 公式 OpenAPI は契約として何を保証するか
  - リクエストプロパティの受理性は記述されているが、レスポンススキーマとエラーボディ構造は定義されていない
  - 数値制約（`temperature: 0..2` 等）は実機で強制されない事実があり、仕様書と実機の整合性は保証されていない
- §4.4 三層モデルとの対応（HTTP / 推論エンジン / モデル本体の責務）
  - §5 以降の非互換・注意・罠を「どの層の問題か」で分類する用語装置として 1 段落で導入

### §5 Sakura が公式 OpenAI と異なる4箇所（非互換）

各小節は「症状 → なぜ起こるか → RubyLLM での対処コード」の構成で 1 件 200〜400 字。

- §5.1 `tool_choice: none` が無視される
  - Sakura `gpt-oss-120b` は `none` 指定でも `tool_calls` を返す。公式 OpenAI `gpt-4o-mini` は仕様通り抑制
  - 推論エンジン層の vLLM 起動オプション差異が原因と推測される
  - 対処: `tool_choice: 'none'` を信頼せず、tool 抑制したい場面では `tools` パラメータ自体を渡さない
- §5.2 OpenAPI の数値制約が実機で強制されない
  - `temperature: 99.9`、`max_tokens: 10_000_000` が 200 で受理される
  - Sakura OpenAPI には `temperature: 0..2` / `max_tokens: minimum 1` が明示されているのに HTTP 層でバリデーションされていない
  - 対処: クライアント側で範囲検証する具体コード
- §5.3 エラー応答の HTTP ステータス・ボディ構造
  - 不明モデルは 400 vs 公式 OpenAI 404、エラーボディは `{error:{message}}` のみで `type / param / code` 不在
  - 対処: HTTP ステータスのみで分岐、`error.code` 前提の OpenAI 互換クライアント分岐は外す
- §5.4 `response_format`（`json_schema`）が効かない
  - Sakura OpenAPI に `response_format` の記載がなく、実機でも 4 モデルで効果が確認できない
  - RubyLLM の `with_schema` は OpenAI 仕様準拠の payload を送出している（webmock で確認済み）が、サーバ側で参照されない
  - 対処: `with_schema` を「型安全な構造化出力」として信頼しない設計、戻り値型のアサート

### §6 Sakura で気をつけるべき4つの差異（注意）

- §6.1 `tool_choice: named` の `finish_reason` 差
  - Sakura: `tool_calls` / OpenAI: `stop`。tool_calls 配列の中身は一致
  - 対処: 会話終端判定は `finish_reason` だけでなく `tool_calls` の有無でも見る
- §6.2 応答ボディに OpenAPI 仕様外のフィールドが含まれる
  - top-level に `prompt_logprobs`, `prompt_token_ids`, `kv_transfer_params`、message に `reasoning_content`, `function_call` 等
  - vLLM 系の拡張フィールドが透過しているため
  - 対処: strict-typed パーサを避ける、未知フィールドを許容
- §6.3 streaming `usage` chunk の既定送信
  - Sakura は `stream_options.include_usage` 無指定でも usage chunk を送る。公式 OpenAI は明示時のみ
  - 対処: stream パーサは終端後に usage chunk が来る前提
- §6.4 vision `image_url` 文言と実機受理の差
  - Sakura OpenAPI 文言は base64 限定だが、実機は外部 HTTPS URL も 200 で受理
  - 対処: 暗黙仕様として依存しすぎず、可能な範囲で base64 経路を併用

### §7 RubyLLM 側に潜む4つの罠

互換性ギャップの「クライアント実装側の差」をまとめる。Sakura の話ではなく、RubyLLM 1.15.0 が OpenAI 互換クライアントとして汎用化されているために生じる挙動。

- §7.1 registry の同名モデル ID 衝突
  - `gpt-oss-120b` は Azure/Bedrock/OpenRouter 配下に登録済み。`provider:` 省略で `Models.find` が他 provider を返し `azure_*` 系設定要求の `ConfigurationError` が出る
  - 対処: `provider: :openai, assume_model_exists: true` を必須化
- §7.2 `with_schema` は JSON.parse 失敗時に String を返す
  - [`chat.rb#L172-L178`](https://github.com/crmne/ruby_llm/blob/ff392893bb5366937688fa82bc0841185491f84c/lib/ruby_llm/chat.rb#L172-L178) のサイレントフォールバック
  - Sakura 側で response_format が効かない（§5.4）と組み合わさると、`response.content.is_a?(Hash)` は `false` に
  - 対処: `is_a?(Hash)` アサート + 失敗時の例外設計
- §7.3 429 を自動リトライする — 多重課金リスク
  - [`connection.rb#L102-L114`](https://github.com/crmne/ruby_llm/blob/ff392893bb5366937688fa82bc0841185491f84c/lib/ruby_llm/connection.rb#L102-L114) で 429 が POST も自動リトライ対象
  - 無償プラン超過 → 自動再送 → 従量課金プランで多重請求の経路
  - 対処: `c.max_retries = 0` または特定例外のみ無効化する monkey patch
- §7.4 system ロールの developer 変換
  - 既定（`nil`）だと system が `developer` ロール文字列で送出される（OpenAI 新仕様向け）
  - Sakura 側で `developer` ロールを期待動作で扱う保証はない
  - 対処: `c.openai_use_system_role = true` を明示

### §8 本番投入前のチェックリスト

各項目に該当する記事内のセクションへの内部リンクを併記。

- [ ] `provider: :openai, assume_model_exists: true, openai_use_system_role: true` を設定（§3, §7.1, §7.4）
- [ ] エラー分岐は HTTP ステータスのみで行う。`error.code` を見ない（§5.3）
- [ ] `temperature` `max_tokens` をクライアント側で範囲検証（§5.2）
- [ ] `with_schema` の戻り型を `is_a?(Hash)` でアサート、enum/required は別途バリデーション（§5.4, §7.2）
- [ ] `c.max_retries = 0` または 429 ハンドリングで多重課金回避（§7.3）
- [ ] streaming パーサは usage chunk が無指定でも来る前提にする（§6.3）

### §9 まとめ

- 「OpenAI 互換」の二段構えで読み解けば、現象は予測できる
- 4 + 4 + 4 のギャップを実装の防御点として落とし込む
- 時点性: 2026-05-09 検証。Sakura は GA 開始 8 ヶ月で実装は変化中、半年〜1 年での再確認推奨
- 検証 probe スクリプト（`bin/probe`）で再検証可能

### §10 付録: 検証環境と参照

- 検証日、Ruby、ruby_llm、ruby_llm-schema バージョン
- Sakura 公式マニュアル / 公式 OpenAPI 仕様 / 公式 OpenAI vision ガイド / vLLM 公式ドキュメント
- 検証 probe / 検証ログのリポジトリ参照
- 詳細マトリクス（モデル別の地雷）への内部リンク（旧記事相当の `compatibility-matrix.md`）

## フラクタル構造の確認

- 記事全体: §2 総論（互換は HTTP レベルまで、4+4+4 のギャップ）→ §3 解決策サマリー → §4〜§7 各論 → §8 チェックリスト → §9 まとめ ✓
- 各 h2 セクション: 冒頭の総論文 → 詳細 → 結論文 を Phase 3 で執筆ルールとして要求
- §5 / §6 / §7 の各小節（h3）: 「症状 → 原因 → 対処」の同一フォーマットで揃え、トラブルシューティング索引としても機能 ✓
- §8 チェックリスト: §5〜§7 の各項目への内部リンクで再導線 ✓

## ソース資料の紐付け

| セクション | 参照する一次ソース |
|---|---|
| §2 総論、§4 二段構え | `docs/reports/sakura-openapi-vs-openai-compatibility.md` 概要・分析 |
| §3 解決策サマリー | 旧 `docs/article.old/draft.md` §解決策サマリー＋本記事独自の `max_retries = 0` 追加 |
| §4.3 Sakura OpenAPI の限界 | `docs/reports/sakura-openapi-vs-openai-compatibility.md` §1.1, §6.1 |
| §5.1 tool_choice none | `tmp/probe_results/sakura__d_tools__gpt-oss-120b.json` + 旧 draft §モデル別地雷 |
| §5.2 OpenAPI 制約強制 | `tmp/probe_results/sakura__g_errors__gpt-oss-120b.json` + 同レポート §6 |
| §5.3 エラー応答 | 同レポート §6.1 + 旧 draft TS-11 |
| §5.4 response_format | 旧 draft 「構造化出力は さくらのAI Engine で機能しない」節（4 モデル横断の事実は流用、本記事では 1 段落要約） |
| §6.1 named finish_reason | 同レポート §3.2 |
| §6.2 拡張フィールド | 同レポート §1.1 |
| §6.3 streaming usage | 同レポート §4 |
| §6.4 vision URL/base64 | 同レポート §5 + 旧 draft Vision 節 |
| §7.1 registry 衝突 | 旧 draft 環境セットアップ＋RubyLLM 1.15.0 ソース |
| §7.2 サイレント String | 旧 draft §構造化出力 + RubyLLM `chat.rb` |
| §7.3 429 自動リトライ | 旧 draft TS-17 + RubyLLM `connection.rb` |
| §7.4 developer 変換 | 旧 draft TS-15 + RubyLLM `providers/openai/chat.rb` |

## 旧 draft からの構成変更方針

- **モデル別の地雷マップ（旧 §モデル別の地雷マップ）は採用しない**
  - 理由: 本記事は API 互換性に主眼を置くため、モデル別の挙動差は副題（旧記事相当の `compatibility-matrix.md` への外部リンク）に留める
  - 旧 §gpt-oss-120b の reasoning_content 枯渇、§Phi-4-mini の tools 不安定 等は付録で 1 行ずつ言及するに留める
- **「三層モデル」の独立 h2 から、§4 の 1 サブセクションに格下げ**
  - 理由: 本記事の論理装置は「OpenAI 互換の二段構え」と「契約レベル vs クライアント実装」の 2 軸であり、三層モデルは補助概念
- **トラブルシューティング索引（旧 §ハマりやすい組み合わせ）を §5/§6/§7 の小節と統合**
  - 理由: 「症状 → 原因 → 対処」のフォーマットを各論セクションに直接埋め込むことで、別索引としての二重提示を避ける
- **`response_format` の 4 モデル横断の詳細データ（旧 §構造化出力は機能しない）は §5.4 で 1 段落要約**
  - 理由: 本記事の主張は「Sakura OpenAPI に未定義 → 効かない」と「RubyLLM `with_schema` のサイレントフォールバック」の 2 点に絞る
  - 旧記事のモデル別の癖（Markdown コードブロック、enum 違反等）は付録で簡潔に列挙

## 既存ドラフトとの関係

旧 `docs/article.old/draft.md`（約 13,000 字）は「モデル × 機能」の網羅性を重視した構成。本アウトラインはユーザー指示に従い、構成を継承せず以下に再設計する:

- 主軸を「モデル別」から「API 互換性レイヤ別」に変更
- RubyLLM 1.15.0 のクライアント実装に起因する罠を独立 h2（§7）として明示
- 公式 OpenAI 実機との対比（`docs/reports/sakura-openapi-vs-openai-compatibility.md`）を一次ソースとして優先
