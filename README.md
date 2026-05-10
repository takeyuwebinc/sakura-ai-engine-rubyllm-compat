# sakura-ai-engine-rubyllm-compat

さくらインターネット「AI Engine」の OpenAI 互換 API を [RubyLLM](https://github.com/crmne/ruby_llm) から利用する際の互換性・落とし穴を実機検証したリポジトリ。

- **対象 API**: `https://api.ai.sakura.ad.jp/v1`
- **対象 gem**: `ruby_llm` 1.15 系 / `ruby_llm-schema`
- **最終確認日**: 2026-05-09
- **検証 Ruby**: 4.0.2

検証結果と知見は [docs/](docs/) 配下にまとまっている。リポジトリ自体は実行可能な検証スクリプト（probe）と、本物のキーで気軽に叩ける IRB コンソールを提供する。

## 主要成果物

| 種別 | パス |
|---|---|
| 互換性マトリクス | [docs/reports/compatibility-matrix.md](docs/reports/compatibility-matrix.md) |
| トラブルシューティング集 | [docs/reports/troubleshooting.md](docs/reports/troubleshooting.md) |
| ファクトチェック報告 | [docs/reports/fact-check-report.md](docs/reports/fact-check-report.md) |
| 横断整合性チェック | [docs/reports/cross-consistency-report.md](docs/reports/cross-consistency-report.md) |
| 公式情報サマリ | [docs/research/01-sakura-official.md](docs/research/01-sakura-official.md) |
| RubyLLM 内部読解メモ | [docs/research/02-rubyllm-internals.md](docs/research/02-rubyllm-internals.md) |
| 技術記事ドラフト | [docs/article/draft.md](docs/article/draft.md) |

## セットアップ

1. Ruby 3.2 以上 + Bundler を用意（検証時は rbenv 4.0.2）。
2. 依存 gem を入れる。
   ```sh
   bundle install
   ```
3. AI Engine の API キーを `.env` に設定する（`.gitignore` 済み）。
   ```sh
   echo 'SAKURA_AI_ACCOUNT_KEY=<UUID>:<シークレット>' > .env
   ```
   キー形式は `<アカウントID(UUID)>:<シークレット>` の 1 文字列。詳細は [docs/research/01-sakura-official.md](docs/research/01-sakura-official.md)。
4. 公式 OpenAI API と比較したい場合は、同じ `.env` に OpenAI のキーも追加する（`--provider openai` 指定時のみ使用される）。
   ```sh
   echo 'OPENAI_API_KEY=sk-...' >> .env
   ```
   `OPENAI_API_BASE` も任意で上書き可能（既定: `https://api.openai.com/v1`）。

## プロバイダ切替

probe / console は Sakura AI Engine と公式 OpenAI API のいずれにも実行できる。デフォルトは `sakura`（後方互換）で、明示的にプロバイダを切り替えるには以下のいずれかを使う。

| 方法 | 例 |
|---|---|
| `--provider <name>` フラグ | `bundle exec bin/probe a_connect --provider openai` |
| `PROBE_PROVIDER` 環境変数 | `PROBE_PROVIDER=openai bundle exec bin/probe a_connect` |

切替対象は次のとおり：

- `ProbeRunner.api_base` / `api_key` / `default_chat_model` / `default_vision_model`
- 結果 JSON のファイル名（`<provider>__<probe>__<model>.json`）と最上位の `provider` / `api_base` キー
- `bin/console` 内の `models` ショートハンド（`SakuraModels` または `OpenAIModels` を返す）

> **注意**: `--provider openai` 指定時は公式 OpenAI API への実機リクエストが発生し、API キー保有者の課金が発生する。デフォルトの実行先は Sakura のままなので、明示的に切り替えた場合のみ叩かれる。

## bin/console — RubyLLM をすぐ試す

`.env` のキーで RubyLLM を Sakura 向けに configure 済みの IRB を起動する。コードを書かずに対話で叩きたい時用。

### 起動

```sh
bundle exec bin/console
```

> システム Ruby ではなく Bundler 管理下の Ruby が必要。`bin/console` を直叩きすると `Bundler::GemNotFound` になる場合は `bundle exec` 経由で起動すること。

### IRB 内で使えるショートハンド

| 名称 | 役割 |
|---|---|
| `chat` | 現在のプロバイダの代表モデル（Sakura: `gpt-oss-120b` / OpenAI: `gpt-4o-mini`）に対する `RubyLLM::Chat` を返す。`chat(model: "...")` で任意モデル切替。 |
| `models` | プロバイダに応じて [SakuraModels](lib/sakura_models.rb) または [OpenAIModels](lib/openai_models.rb) 定数群を返す（`REPRESENTATIVE` / `REPRESENTATIVE_VISION` / `TEXT_TARGETS` / `VISION_TARGETS` を共通で提供）。 |
| `ProbeRunner.raw_post(path:, payload:)` | RubyLLM を介さず直接 HTTP を叩く。互換性検証で素の応答を見たい時用。 |

### 使用例

```ruby
# 単発の chat
chat.ask("こんにちは").content

# モデル切替
chat(model: "Qwen3-Coder-30B-A3B-Instruct").ask("Rubyで素数判定を書いて").content

# vision モデル（preview/）
chat(model: "preview/Qwen3-VL-30B-A3B-Instruct")
  .ask("この画像を説明して", with: "path/to/image.png")
  .content

# モデル一覧
models::GA_TEXT          # => ["gpt-oss-120b", "llm-jp-3.1-8x13b-instruct4", ...]
models::REPRESENTATIVE   # => "gpt-oss-120b"

# OpenAI SDK では弾かれる値が AI Engine では 200 で通る挙動を確認
ProbeRunner.raw_post(
  path: "chat/completions",
  payload: { model: "gpt-oss-120b", messages: [{ role: "user", content: "ping" }], temperature: 99.9 }
).fetch(:status) # => 200
```

設定の中身（`openai_api_base`、`assume_model_exists: true` など）は [lib/probe_runner.rb](lib/probe_runner.rb) を参照。

## bin/probe — 実機検証スクリプトの再実行

調査用に書かれた個別 probe を再実行できる。結果は `tmp/probe_results/<provider>__<probe>__<model>.json` に書き出される（`.gitignore` 済み）。

```sh
bundle exec bin/probe a_connect      # 接続・認証（既定で Sakura）
bundle exec bin/probe b_models       # GET /v1/models
bundle exec bin/probe c_schema       # 構造化出力 (JSON Schema)
bundle exec bin/probe d_tools        # Tool calling
bundle exec bin/probe e_streaming    # SSE streaming
bundle exec bin/probe f_vision       # Vision (画像入力)
bundle exec bin/probe g_errors       # エラーハンドリング
bundle exec bin/probe h_params       # 基本パラメータ受理性

# 公式 OpenAI に対して同じ probe を実行
bundle exec bin/probe a_connect --provider openai
```

各 probe の意図と判定基準は [docs/reports/compatibility-matrix.md](docs/reports/compatibility-matrix.md) と各 probe の冒頭コメントを参照。

## bin/compare — Sakura と OpenAI の結果差分を表示

両プロバイダで同じ probe を実行した後に、結果 JSON のシナリオごとの差分を表形式で出力する。

```sh
bundle exec bin/probe a_connect                    # → sakura__a_connect__gpt-oss-120b.json
bundle exec bin/probe a_connect --provider openai  # → openai__a_connect__gpt-4o-mini.json
bundle exec bin/compare a_connect                  # 差分表示
```

旧形式（プロバイダ接頭辞なし、`<probe>__<model>.json`）のファイルは比較対象外。`tmp/probe_results/` を一度クリアしてから再実行すると差分が綺麗に揃う。

## ディレクトリ構成

```
.
├── bin/
│   ├── console          # RubyLLM を Sakura 向けに configure した IRB
│   └── probe            # 個別 probe ランチャ
├── lib/
│   ├── probe_runner.rb  # RubyLLM 設定 / 直接 HTTP / 結果記録の共通モジュール
│   ├── sakura_models.rb # /v1/models 実機確認結果に基づく定数群
│   └── probes/          # a_connect 〜 h_params の検証スクリプト
├── docs/
│   ├── research/        # 公式情報・RubyLLM 内部の読解メモ
│   ├── reports/         # 互換性マトリクス・トラブルシューティング・各種レビュー
│   ├── article/         # 技術記事ドラフトと作成ログ
│   └── workflow/        # ワークフロー進捗
└── tmp/probe_results/   # probe 実行ログ（.gitignore 対象）
```

## 注意事項

- **API キーを成果物に混ぜない**: ログ・記事・コミットメッセージに `.env` の値を貼らないこと。`.env` 自体は `.gitignore` 済み。
- **preview モデルは時点性が高い**: `preview/` プレフィックスのモデルは予告なくラインナップが変わる。最新は `bin/probe b_models` で確認する。
- **公式マニュアルと API model 文字列は一致しない**: `GET /v1/models` の結果が権威ソース。背景は [compatibility-matrix.md §3](docs/reports/compatibility-matrix.md) 参照。
- **OpenAPI 上の制約は実機で強制されない**: `temperature: 99.9` や `max_tokens: 10_000_000` も 200 が返る。詳細は [troubleshooting.md](docs/reports/troubleshooting.md)。
