# ドキュメントワークフロー進捗

## プロジェクト情報

- **ワークフローID**: sakura-ai-rubyllm
- **プロジェクト名**: さくらのAI Engine の OpenAI 互換性 × RubyLLM 利用上の落とし穴 調査
- **開始日**: 2026-05-09
- **最終更新日**: 2026-05-09
- **ステータス**: 完了

## ワークフロー方針

plan.md は調査計画書として既に確定しているため、doc-orchestration の標準フェーズ
（要件定義 → 用語集 → 機能設計 → 調査報告 → ADR）は適合しない。
代わりに plan.md §8「着手順序の推奨」に基づく独自フェーズで実施する。

最終成果物は以下の 2 種:
- **調査報告書**（report-creation スキル相当）— モデル × 機能マトリクスとトラブルシューティング集
- **技術記事**（technical-article スキル相当）— Zenn/Qiita 向けドラフト

## 制約と前提

- **API キー利用可能**: `.env` に `SAKURA_AI_ACCOUNT_KEY` 設定済み（2026-05-09）。実機検証フェーズも本セッションで実行可能
- **API キーの取扱い**: `.env` を `.gitignore` で除外。値を成果物（記事・ログ）に含めない運用とする
- Ruby 4.0.2 / Bundler 利用可能。`ruby_llm` gem は未インストールのため Phase 5 で `bundle install`
- 検証プロジェクトは Rails ではなく Bundler + 単一 Ruby スクリプトに縮約（plan.md §4.3.3 から軽量化）
- plan.md 全体の想定工数は 5.25 人日。1 セッションで全部は終わらない可能性が高いが、API キー利用可能になったため工程の中断点が大幅に減った

## ワークフロー進捗

- [x] Phase 1: インベントリと計画
- [x] Phase 2: 検証スコープ・代表モデル確定（plan.md §3.5.1 を実機確認結果で更新）
- [x] Phase 3: 公式情報の精読（plan.md §4.1）
- [x] Phase 4: RubyLLM ソース読解（plan.md §4.2）
- [x] Phase 5: 検証用プロジェクト構築（plan.md §4.3.3 を Bundler + 単一 Ruby スクリプトに縮約）
- [x] Phase 6: 実機検証 — モデル非依存項目（A / B / G / H）
- [x] Phase 7: 実機検証 — 構造化出力・Tools（C / D 代表 + 横展開済）
- [x] Phase 8: 実機検証 — Streaming / Vision（E / F 代表 + 横展開済）
- [x] Phase 9: マトリクス整理・トラブルシューティング集（plan.md §5.1, §5.2）
- [x] Phase 10: ファクトチェック（重要 1 / 中 3 / 軽微 4 → すべて修正反映済）
- [x] Phase 11: 記事ドラフト執筆（plan.md §5.4）
- [x] Phase 12: 完了レビュー（横断整合性チェック完了 → 重要1/中1/任意 の修正全て反映済）

## 成果物一覧

| 文書種別 | タイトル | ステータス | ファイルパス |
|---------|---------|-----------|------------|
| 調査計画書 | 調査計画 | 完了（既存） | plan.md |
| 公式情報メモ | Sakura AI Engine 公式情報サマリ | 未着手 | docs/research/01-sakura-official.md |
| RubyLLM 読解メモ | RubyLLM 該当箇所読解メモ | 完了（2026-05-09） | docs/research/02-rubyllm-internals.md |
| 検証プロジェクト | probe scaffold | 完了 | lib/probes/, bin/probe |
| 実機検証ログ | モデル × 機能 実機検証結果 | 完了 | tmp/probe_results/*.json |
| 調査報告書 | モデル × 機能 互換性マトリクス | 完了 | docs/reports/compatibility-matrix.md |
| トラブルシューティング集 | エラー症状 → 原因 → 対処 | 完了（20件） | docs/reports/troubleshooting.md |
| ファクトチェック報告 | 主張の裏どり結果 | 完了（重要1/中3/軽微4 → 全件反映済） | docs/reports/fact-check-report.md |
| 記事アウトライン | Zenn/Qiita 記事構成 | 完了 | docs/article/outline.md |
| 技術記事ドラフト | Zenn/Qiita 記事本文 | 完了 | docs/article/draft.md |
| 横断整合性チェック | 文書間の矛盾検出 | 完了（重要1件 + 軽微 → 全件反映済） | docs/reports/cross-consistency-report.md |

## 各フェーズの実施可能性

| Phase | 内容 | 単独セッションで可能 | 必要前提 |
|---|---|---|---|
| 1 | 計画 | ✓ | — |
| 2 | スコープ確定 | ✓ | ユーザー判断 |
| 3 | 公式情報精読 | ✓ | WebFetch |
| 4 | RubyLLM 読解 | ✓ | GitHub アクセス |
| 5 | 検証プロジェクト構築 | ✓ | Ruby/Bundler |
| 6〜8 | 実機検証 | ✓ | Sakura API キー（取得済） |
| 9 | マトリクス整理 | ✓ | Phase 6〜8 完了 |
| 10 | ファクトチェック | ✓ | Phase 9 完了 |
| 11 | 記事執筆 | ✓ | Phase 9 完了 |
| 12 | 完了レビュー | ✓ | 全フェーズ完了 |

## 備考

- plan.md §1 で「読者像（LLM 内部に詳しくない Rails エンジニア）」が明確化されているため、記事執筆では概念整理セクション（plan.md §5.5）の比重が高い
- preview モデルの動作は時点性が極めて高い。最終確認日を全成果物に明記する運用を取る
- クローズドモデル（PLaMo / cotomi）は対象外（plan.md §3.5.1）
