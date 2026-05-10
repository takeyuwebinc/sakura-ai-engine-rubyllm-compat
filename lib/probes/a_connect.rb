# frozen_string_literal: true

require_relative '../probe_runner'

module Probes
  module AConnect
    module_function

    def run(model_id = nil)
      model_id ||= ProbeRunner.default_chat_model
      ProbeRunner.configure_ruby_llm
      result = {
        purpose: 'A: 接続・認証・基本パラメータの疎通確認',
        scenarios: {}
      }

      result[:scenarios][:raw_minimal] = scenario_raw_minimal(model_id)
      result[:scenarios][:raw_with_system] = scenario_raw_with_system(model_id)
      result[:scenarios][:raw_with_developer] = scenario_raw_with_developer(model_id)
      result[:scenarios][:rubyllm_basic] = scenario_rubyllm_basic(model_id)
      result[:scenarios][:rubyllm_system_role_off] = scenario_rubyllm_system_role_off(model_id)

      path = ProbeRunner.record('a_connect', model_id, result)
      puts "Saved: #{path}"
      print_summary(result)
    end

    def scenario_raw_minimal(model_id)
      ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [{ role: 'user', content: 'pingに「pong」とだけ答えて' }],
          max_tokens: 16,
          temperature: 0
        }
      )
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_raw_with_system(model_id)
      ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [
            { role: 'system', content: 'あなたは簡潔に答えるAIです' },
            { role: 'user', content: 'pingに「pong」とだけ答えて' }
          ],
          max_tokens: 16,
          temperature: 0
        }
      )
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_raw_with_developer(model_id)
      ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [
            { role: 'developer', content: 'あなたは簡潔に答えるAIです' },
            { role: 'user', content: 'pingに「pong」とだけ答えて' }
          ],
          max_tokens: 16,
          temperature: 0
        }
      )
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_rubyllm_basic(model_id)
      chat = ProbeRunner.chat(model: model_id)
      msg = chat.with_temperature(0).ask('pingに「pong」とだけ答えて')
      {
        ok: true,
        content: msg.content,
        role: msg.role,
        model_id_returned: msg.model_id,
        input_tokens: msg.input_tokens,
        output_tokens: msg.output_tokens,
        thinking_present: !msg.thinking.nil?
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_rubyllm_system_role_off(model_id)
      RubyLLM.configure { |c| c.openai_use_system_role = false }
      chat = ProbeRunner.chat(model: model_id)
      msg = chat
            .with_instructions('あなたは簡潔に答えるAIです')
            .with_temperature(0)
            .ask('pingに「pong」とだけ答えて')
      {
        ok: true,
        content: msg.content,
        note: 'system role が developer として送られた状態での挙動'
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    ensure
      RubyLLM.configure { |c| c.openai_use_system_role = true }
    end

    def print_summary(result)
      puts "\n=== Summary ==="
      result[:scenarios].each do |name, r|
        if r.is_a?(Hash) && r[:status]
          puts format('  %-32s HTTP %d (%dms)', name, r[:status], r[:duration_ms])
        elsif r.is_a?(Hash) && r[:ok]
          content = r[:content].to_s[0, 60].gsub("\n", ' ')
          puts format('  %-32s OK  content=%s', name, content.inspect)
        elsif r.is_a?(Hash) && r[:class]
          puts format('  %-32s ERROR %s: %s', name, r[:class], r[:message])
        else
          puts format('  %-32s %s', name, r.inspect[0, 60])
        end
      end
    end
  end
end
