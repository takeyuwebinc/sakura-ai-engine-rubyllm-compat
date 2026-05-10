# frozen_string_literal: true

# Sakura AI Engine /v1/models 実機確認結果（2026-05-09）
# `bin/probe b_models` および GET /v1/models の出力に基づく
module SakuraModels
  # チャットモデル（GA）
  GA_TEXT = %w[
    gpt-oss-120b
    llm-jp-3.1-8x13b-instruct4
    Qwen3-Coder-30B-A3B-Instruct
    Qwen3-Coder-480B-A35B-Instruct-FP8
  ].freeze

  # チャットモデル（preview）
  PREVIEW_TEXT = %w[
    preview/Qwen3-0.6B-cpu
    preview/Phi-4-mini-instruct-cpu
  ].freeze

  PREVIEW_VISION = %w[
    preview/Qwen3-VL-30B-A3B-Instruct
    preview/Phi-4-multimodal-instruct
  ].freeze

  EMBEDDINGS = %w[
    multilingual-e5-large
    preview/Qwen3-Embedding-4B-FP16
  ].freeze

  AUDIO = %w[
    whisper-large-v3-turbo
  ].freeze

  # 代表モデル（plan.md §3.5.3）
  REPRESENTATIVE = 'gpt-oss-120b'

  # plan.md §3.5.3 戦略の検証対象（テキスト系・横展開対象）
  TEXT_TARGETS = (GA_TEXT - %w[Qwen3-Coder-480B-A35B-Instruct-FP8] + PREVIEW_TEXT).freeze
  # 480B は 30B 版で代表取れるため通常スコープから除外（plan.md §3.5.1）

  # vision 検証対象
  VISION_TARGETS = PREVIEW_VISION
end
