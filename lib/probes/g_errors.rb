# frozen_string_literal: true

require_relative '../probe_runner'

module Probes
  module GErrors
    module_function

    def run(model_id = nil)
      model_id ||= ProbeRunner.default_chat_model
      ProbeRunner.configure_ruby_llm
      result = {
        purpose: 'G: エラーハンドリング — HTTP ステータスと RubyLLM 例外マッピング',
        model: model_id,
        scenarios: {}
      }

      result[:scenarios][:no_auth_header] = scenario_no_auth_header(model_id)
      result[:scenarios][:invalid_token] = scenario_invalid_token(model_id)
      result[:scenarios][:unknown_model] = scenario_unknown_model
      result[:scenarios][:invalid_temperature] = scenario_invalid_temperature(model_id)
      result[:scenarios][:huge_max_tokens] = scenario_huge_max_tokens(model_id)
      result[:scenarios][:rubyllm_unauthorized] = scenario_rubyllm_unauthorized(model_id)
      result[:scenarios][:rubyllm_unknown_model] = scenario_rubyllm_unknown_model

      path = ProbeRunner.record('g_errors', model_id, result)
      puts "Saved: #{path}"
      print_summary(result)
    end

    def scenario_no_auth_header(model_id)
      uri = URI.join("#{ProbeRunner.api_base}/", 'chat/completions')
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/json'
      req.body = JSON.generate(
        model: model_id,
        messages: [{ role: 'user', content: 'ping' }],
        max_tokens: 8
      )
      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
      { status: resp.code.to_i, body_head: resp.body.to_s[0, 200], body_parsed: ProbeRunner.safe_json(resp.body) }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_invalid_token(model_id)
      uri = URI.join("#{ProbeRunner.api_base}/", 'chat/completions')
      req = Net::HTTP::Post.new(uri)
      req['Authorization'] = 'Bearer invalid-token-xxxxxxxxxxxxxxxx'
      req['Content-Type'] = 'application/json'
      req.body = JSON.generate(
        model: model_id,
        messages: [{ role: 'user', content: 'ping' }],
        max_tokens: 8
      )
      resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
      { status: resp.code.to_i, body_head: resp.body.to_s[0, 200], body_parsed: ProbeRunner.safe_json(resp.body) }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_unknown_model
      r = ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: 'definitely-not-a-real-model-12345',
          messages: [{ role: 'user', content: 'ping' }],
          max_tokens: 8
        }
      )
      { status: r[:status], body_parsed: r[:body_parsed] }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_invalid_temperature(model_id)
      r = ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [{ role: 'user', content: 'ping' }],
          max_tokens: 8,
          temperature: 99.9 # OpenAPI: max 2
        }
      )
      { status: r[:status], body_parsed: r[:body_parsed] }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_huge_max_tokens(model_id)
      r = ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [{ role: 'user', content: 'ping' }],
          max_tokens: 10_000_000
        }
      )
      { status: r[:status], body_parsed: r[:body_parsed] }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_rubyllm_unauthorized(model_id)
      original_key = RubyLLM.config.openai_api_key
      RubyLLM.configure { |c| c.openai_api_key = 'invalid-token-xxxxxxxxxxxxxxxx' }
      chat = ProbeRunner.chat(model: model_id)
      msg = chat.with_temperature(0).ask('ping')
      { ok: true, content: msg.content }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    ensure
      RubyLLM.configure { |c| c.openai_api_key = original_key }
    end

    def scenario_rubyllm_unknown_model
      chat = ProbeRunner.chat(model: 'definitely-not-a-real-model-12345')
      msg = chat.with_temperature(0).ask('ping')
      { ok: true, content: msg.content }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def print_summary(result)
      puts "\n=== Summary (model: #{result[:model]}) ==="
      result[:scenarios].each do |name, r|
        if r[:status]
          tag = r[:status].between?(200, 299) ? 'OK ' : 'NG '
          err = r[:body_parsed].is_a?(Hash) ? (r[:body_parsed].dig('error', 'message') || r[:body_parsed]['detail']) : nil
          puts format('  %s %-32s HTTP %d%s', tag, name, r[:status], err ? " err=#{err.to_s[0, 80]}" : '')
          puts "      body=#{r[:body_head][0, 200].inspect}" if r[:body_head] && !err
        elsif r[:ok]
          puts format('  OK  %-32s content=%s', name, r[:content].to_s[0, 60].inspect)
        else
          puts format('  ERR %-32s %s: %s', name, r[:class], r[:message].to_s[0, 80])
        end
      end
    end
  end
end
