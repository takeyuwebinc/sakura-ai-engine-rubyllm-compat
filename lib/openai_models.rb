# frozen_string_literal: true

# OpenAI 公式 API の検証対象モデル定義。
# SakuraModels と同一インターフェース（REPRESENTATIVE / REPRESENTATIVE_VISION /
# TEXT_TARGETS / VISION_TARGETS）を提供し、probe 群が両プロバイダで動作するための定数源とする。
module OpenAIModels
  # チャット代表モデル。低コスト・vision 兼用のため検証横展開に適する
  REPRESENTATIVE = 'gpt-4o-mini'

  # Vision 検証用代表モデル（公式 Vision 対応）
  REPRESENTATIVE_VISION = 'gpt-4o-mini'

  # テキスト検証対象（Sakura 側 TEXT_TARGETS と件数オーダーを揃える）
  TEXT_TARGETS = %w[
    gpt-4o-mini
    gpt-4o
    gpt-4.1-mini
  ].freeze

  # Vision 検証対象
  VISION_TARGETS = %w[
    gpt-4o-mini
    gpt-4o
  ].freeze
end
