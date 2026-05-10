# frozen_string_literal: true

require_relative '../probe_runner'
require 'base64'

module Probes
  module FVision
    # 外部 HTTPS URL の例（Python 公式ロゴ）
    EXTERNAL_URL = 'https://www.python.org/static/img/python-logo.png'
    LOCAL_IMAGE_PATH = File.expand_path('../../tmp/images/sample.png', __dir__)

    PROMPT = 'この画像に何が写っていますか？日本語で 1 行で簡潔に答えて'

    module_function

    def run(model_id = nil)
      model_id ||= ProbeRunner.default_vision_model
      ProbeRunner.configure_ruby_llm
      result = {
        purpose: 'F: Vision（image_url）の実機受理性と外部 URL/base64 の差',
        model: model_id,
        scenarios: {}
      }

      result[:scenarios][:raw_external_url] = scenario_raw_external_url(model_id)
      result[:scenarios][:raw_base64] = scenario_raw_base64(model_id)
      result[:scenarios][:rubyllm_with_image_path] = scenario_rubyllm_with_image_path(model_id)

      path = ProbeRunner.record('f_vision', model_id, result)
      puts "Saved: #{path}"
      print_summary(result)
    end

    def scenario_raw_external_url(model_id)
      r = ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [{
            role: 'user',
            content: [
              { type: 'text', text: PROMPT },
              { type: 'image_url', image_url: { url: EXTERNAL_URL } }
            ]
          }],
          temperature: 0,
          max_tokens: 128
        }
      )
      summarize(r)
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_raw_base64(model_id)
      data_uri = data_uri_for(LOCAL_IMAGE_PATH, 'image/png')
      r = ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [{
            role: 'user',
            content: [
              { type: 'text', text: PROMPT },
              { type: 'image_url', image_url: { url: data_uri } }
            ]
          }],
          temperature: 0,
          max_tokens: 128
        }
      )
      summarize(r)
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_rubyllm_with_image_path(model_id)
      chat = ProbeRunner.chat(model: model_id)
      msg = chat.with_temperature(0).ask(PROMPT, with: LOCAL_IMAGE_PATH)
      {
        ok: true,
        content: msg.content.to_s,
        content_class: msg.content.class.name
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def data_uri_for(path, mime)
      data = File.binread(path)
      "data:#{mime};base64,#{Base64.strict_encode64(data)}"
    end

    def summarize(raw)
      out = { status: raw[:status], duration_ms: raw[:duration_ms] }
      if raw[:body_parsed].is_a?(Hash)
        choice = raw[:body_parsed].dig('choices', 0, 'message', 'content')
        out[:content] = choice.to_s
        out[:error_message] = raw[:body_parsed].dig('error', 'message')
      else
        out[:body_head] = raw[:body_raw].to_s[0, 200]
      end
      out
    end

    def print_summary(result)
      puts "\n=== Summary (model: #{result[:model]}) ==="
      result[:scenarios].each do |name, r|
        if r[:status]
          tag = r[:status] == 200 ? 'OK ' : 'NG '
          err = r[:error_message] ? " err=#{r[:error_message].to_s[0, 80]}" : ''
          puts format('  %s %-32s HTTP %d%s', tag, name, r[:status], err)
          puts "      content=#{r[:content].to_s[0, 200].inspect}" if r[:content]
        elsif r[:ok]
          puts format('  OK  %-32s class=%s', name, r[:content_class])
          puts "      content=#{r[:content][0, 200].inspect}"
        else
          puts format('  ERR %-32s %s: %s', name, r[:class], r[:message].to_s[0, 80])
        end
      end
    end
  end
end
