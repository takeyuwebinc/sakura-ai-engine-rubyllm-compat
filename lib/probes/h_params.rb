# frozen_string_literal: true

require_relative '../probe_runner'

module Probes
  module HParams
    PROMPT = '0 から 9 までの数字をランダムに 1 つだけ出力して'

    module_function

    def run(model_id = nil)
      model_id ||= ProbeRunner.default_chat_model
      ProbeRunner.configure_ruby_llm
      result = {
        purpose: 'H: OpenAPI 未定義の基本パラメータ（seed/top_p/n/stop/presence_penalty 等）の受理状況',
        model: model_id,
        scenarios: {}
      }

      result[:scenarios][:seed] = scenario_param(model_id, { seed: 42, temperature: 1.0 })
      result[:scenarios][:top_p] = scenario_param(model_id, { top_p: 0.5, temperature: 1.0 })
      result[:scenarios][:n_2] = scenario_param(model_id, { n: 2, temperature: 1.0 })
      result[:scenarios][:stop] = scenario_param(model_id, { stop: ['5'], temperature: 1.0 })
      result[:scenarios][:presence_penalty] = scenario_param(model_id, { presence_penalty: 0.5, temperature: 1.0 })
      result[:scenarios][:frequency_penalty] = scenario_param(model_id, { frequency_penalty: 0.5, temperature: 1.0 })
      result[:scenarios][:logprobs] = scenario_param(model_id, { logprobs: true, top_logprobs: 3, temperature: 1.0 })
      result[:scenarios][:user] = scenario_param(model_id, { user: 'probe-test', temperature: 1.0 })
      result[:scenarios][:nonsense_param] = scenario_param(model_id, { definitely_unknown_param: 'xyz', temperature: 1.0 })

      # seed の再現性確認: 同じ seed で 2 回叩いて同じ結果になるか
      result[:scenarios][:seed_reproducibility] = scenario_seed_reproducibility(model_id)

      path = ProbeRunner.record('h_params', model_id, result)
      puts "Saved: #{path}"
      print_summary(result)
    end

    def scenario_param(model_id, extras)
      base = {
        model: model_id,
        messages: [{ role: 'user', content: PROMPT }],
        max_tokens: 32
      }
      r = ProbeRunner.raw_post(path: 'chat/completions', payload: base.merge(extras))
      summarize(r, extras)
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_seed_reproducibility(model_id)
      runs = 2.times.map do
        r = ProbeRunner.raw_post(
          path: 'chat/completions',
          payload: {
            model: model_id,
            messages: [{ role: 'user', content: PROMPT }],
            max_tokens: 32,
            seed: 4242,
            temperature: 1.0
          }
        )
        r[:body_parsed]&.dig('choices', 0, 'message', 'content')
      end
      {
        run1_content: runs[0],
        run2_content: runs[1],
        identical: runs[0] == runs[1] && !runs[0].nil?
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def summarize(raw, extras)
      out = { status: raw[:status], extras: extras, duration_ms: raw[:duration_ms] }
      if raw[:body_parsed].is_a?(Hash)
        choices = raw[:body_parsed]['choices']
        out[:choice_count] = choices.is_a?(Array) ? choices.size : 0
        out[:content_head] = choices&.dig(0, 'message', 'content').to_s[0, 80]
        out[:logprobs_present] = !choices&.dig(0, 'logprobs').nil?
        out[:error_message] = raw[:body_parsed].dig('error', 'message')
      else
        out[:body_head] = raw[:body_raw].to_s[0, 200]
      end
      out
    end

    def print_summary(result)
      puts "\n=== Summary (model: #{result[:model]}) ==="
      result[:scenarios].each do |name, r|
        next puts(format('  ?   %-32s %s', name, r.inspect[0, 100])) unless r.is_a?(Hash)

        if r[:status]
          tag = r[:status] == 200 ? 'OK ' : 'NG '
          n = r[:choice_count] ? " choices=#{r[:choice_count]}" : ''
          err = r[:error_message] ? " err=#{r[:error_message].to_s[0, 80]}" : ''
          lp = r[:logprobs_present] ? ' LOGPROBS' : ''
          puts format('  %s %-32s HTTP %d%s%s%s', tag, name, r[:status], n, lp, err)
          puts "      content=#{r[:content_head].inspect}" if r[:content_head] && !r[:content_head].empty?
        elsif r.key?(:identical)
          puts format('  %s seed_reproducibility identical=%s', r[:identical] ? 'OK ' : 'NG ', r[:identical])
          puts "      run1=#{r[:run1_content].inspect}"
          puts "      run2=#{r[:run2_content].inspect}"
        else
          puts format('  ERR %-32s %s: %s', name, r[:class], r[:message].to_s[0, 80])
        end
      end
    end
  end
end
