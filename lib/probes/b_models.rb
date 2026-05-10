# frozen_string_literal: true

require_relative '../probe_runner'

module Probes
  module BModels
    # Sakura 専用候補（plan.md §3.5.1 の対象モデル + Phase 3 で発覚した表記揺れ）
    SAKURA_CANDIDATES = [
      # GA テキスト系（plan.md §3.5.1 必須/推奨）
      'gpt-oss-120b',
      'llm-jp-3.1-8x13b-instruct4',
      'Qwen3-Coder-30B-A3B-Instruct',
      'Qwen3-Coder-480B-A35B-Instruct-FP8',
      'Qwen3-0.6B',
      # Phi-4: plan.md は 'Phi-4' と書くが S6 ライセンス表記は Phi-4-mini-instruct
      'Phi-4',
      'Phi-4-mini-instruct',
      # Vision 系: S5 と S6 で表記揺れ。両方試す
      'Qwen3-VL-30B-A3B-Instruct',
      'preview/Qwen3-VL-30B-A3B-Instruct',
      'Phi-4-multimodal-instruct',
      'preview/Phi-4-multimodal-instruct',
      # Kimi
      'Kimi-K2.5',
      # 存在しないモデル（コントロール）
      'definitely-does-not-exist-xxx'
    ].freeze

    module_function

    def candidates
      case ProbeRunner.current_provider
      when :sakura
        SAKURA_CANDIDATES
      when :openai
        require_relative '../openai_models'
        (OpenAIModels::TEXT_TARGETS + OpenAIModels::VISION_TARGETS).uniq + ['definitely-does-not-exist-xxx']
      end
    end

    def run(*_args)
      ProbeRunner.configure_ruby_llm
      result = {
        purpose: 'B: モデル一覧の実機確定（S5/S6 表記揺れの解決）',
        scenarios: {}
      }

      result[:scenarios][:list_endpoint] = scenario_list_endpoint
      result[:scenarios][:per_model] = candidates.to_h { |m| [m, scenario_minimal_request(m)] }

      path = ProbeRunner.record('b_models', 'all', result)
      puts "Saved: #{path}"
      print_summary(result)
    end

    # OpenAPI 未定義だが OpenAI 互換なら GET /v1/models が使えるかもしれない
    def scenario_list_endpoint
      uri = URI.join("#{ProbeRunner.api_base}/", 'models')
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{ProbeRunner.api_key}"
      req['Accept'] = 'application/json'
      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
      {
        url: uri.to_s,
        status: resp.code.to_i,
        body_parsed: ProbeRunner.safe_json(resp.body),
        body_head: resp.body.to_s[0, 300]
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_minimal_request(model_id)
      ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [{ role: 'user', content: 'pingに「pong」とだけ答えて' }],
          max_tokens: 8,
          temperature: 0
        }
      ).tap do |r|
        # body_raw を要約（モデルが認識されたかだけ知りたい）
        r.delete(:body_raw)
        r.delete(:headers)
        if r[:body_parsed].is_a?(Hash)
          choice = r[:body_parsed].dig('choices', 0, 'message', 'content')
          r[:content_head] = choice.to_s[0, 60]
          r[:error_message] = r[:body_parsed].dig('error', 'message') || r[:body_parsed]['detail']
          r[:returned_model] = r[:body_parsed]['model']
          r.delete(:body_parsed)
        end
      end
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def print_summary(result)
      puts "\n=== Models endpoint ==="
      r = result[:scenarios][:list_endpoint]
      puts "  GET /v1/models => HTTP #{r[:status]}"
      puts "  body head: #{r[:body_head].to_s[0, 200].inspect}" if r[:body_head]

      puts "\n=== Per-model availability ==="
      result[:scenarios][:per_model].each do |model_id, r|
        if r[:status]
          tag = r[:status] == 200 ? 'OK ' : 'NG '
          err = r[:error_message] ? " err=#{r[:error_message].to_s[0, 60]}" : ''
          ret = r[:returned_model] ? " returned=#{r[:returned_model]}" : ''
          puts format('  %s %-46s HTTP %d%s%s', tag, model_id, r[:status], ret, err)
        else
          puts format('  ERR %-46s %s', model_id, r[:message])
        end
      end
    end
  end
end
