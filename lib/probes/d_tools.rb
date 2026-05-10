# frozen_string_literal: true

require_relative '../probe_runner'

module Probes
  module DTools
    TOOL_DEF = {
      type: 'function',
      function: {
        name: 'get_weather',
        description: '指定された都市の現在の天気を取得する',
        parameters: {
          type: 'object',
          properties: {
            city: { type: 'string', description: '都市名（例: Tokyo）' }
          },
          required: %w[city],
          additionalProperties: false
        }
      }
    }.freeze

    PROMPT_NEEDS_TOOL = '東京の今の天気を教えて。get_weather ツールがあれば使って'
    PROMPT_NO_TOOL_NEEDED = '1+1 はいくつ？'

    class GetWeather < RubyLLM::Tool
      description '指定された都市の現在の天気を取得する'
      param :city, type: :string, desc: '都市名'

      def execute(city:)
        { city: city, temperature_celsius: 22, condition: 'sunny' }
      end
    end

    module_function

    def run(model_id = nil)
      model_id ||= ProbeRunner.default_chat_model
      ProbeRunner.configure_ruby_llm
      result = {
        purpose: 'D: tools / function calling の実機受理性',
        model: model_id,
        scenarios: {}
      }

      result[:scenarios][:raw_tools_auto] = scenario_raw_tools(model_id, tool_choice: 'auto')
      result[:scenarios][:raw_tools_required] = scenario_raw_tools(model_id, tool_choice: 'required')
      result[:scenarios][:raw_tools_named] = scenario_raw_tools(model_id, tool_choice: { type: 'function', function: { name: 'get_weather' } })
      result[:scenarios][:raw_tools_none] = scenario_raw_tools(model_id, tool_choice: 'none')
      result[:scenarios][:raw_no_tool_needed] = scenario_raw_no_tool_needed(model_id)
      result[:scenarios][:rubyllm_with_tool] = scenario_rubyllm_with_tool(model_id)

      path = ProbeRunner.record('d_tools', model_id, result)
      puts "Saved: #{path}"
      print_summary(result)
    end

    def scenario_raw_tools(model_id, tool_choice:)
      r = ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [{ role: 'user', content: PROMPT_NEEDS_TOOL }],
          temperature: 0,
          max_tokens: 256,
          tools: [TOOL_DEF],
          tool_choice: tool_choice
        }
      )
      summarize(r)
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_raw_no_tool_needed(model_id)
      r = ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [{ role: 'user', content: PROMPT_NO_TOOL_NEEDED }],
          temperature: 0,
          max_tokens: 64,
          tools: [TOOL_DEF],
          tool_choice: 'auto'
        }
      )
      summarize(r)
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_rubyllm_with_tool(model_id)
      chat = ProbeRunner.chat(model: model_id)
      msg = chat.with_tool(GetWeather).with_temperature(0).ask(PROMPT_NEEDS_TOOL)
      {
        ok: true,
        content: msg.content,
        content_class: msg.content.class.name,
        tool_call_present: msg.tool_call?,
        tool_calls: msg.tool_calls&.transform_values { |tc| { name: tc.name, args: tc.arguments } }
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def summarize(raw)
      out = { status: raw[:status], duration_ms: raw[:duration_ms] }
      if raw[:body_parsed].is_a?(Hash)
        msg = raw[:body_parsed].dig('choices', 0, 'message')
        out[:finish_reason] = raw[:body_parsed].dig('choices', 0, 'finish_reason')
        if msg.is_a?(Hash)
          out[:has_tool_calls] = msg['tool_calls'].is_a?(Array) && !msg['tool_calls'].empty?
          out[:tool_calls_summary] = msg['tool_calls']&.map { |tc| { name: tc.dig('function', 'name'), args: tc.dig('function', 'arguments') } }
          out[:content_head] = msg['content'].to_s[0, 120]
        else
          out[:has_tool_calls] = false
          out[:content_head] = nil
        end
        out[:error_message] = raw[:body_parsed].dig('error', 'message')
        out[:full_body_when_error] = raw[:body_parsed] if raw[:status] != 200
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
          tc = r[:has_tool_calls] ? ' TOOL✓' : ' TOOL✗'
          fr = r[:finish_reason] ? " fr=#{r[:finish_reason]}" : ''
          err = r[:error_message] ? " err=#{r[:error_message].to_s[0, 80]}" : ''
          puts format('  %s %-32s HTTP %d%s%s%s', tag, name, r[:status], tc, fr, err)
          puts "      tool_calls=#{r[:tool_calls_summary].inspect[0, 200]}" if r[:has_tool_calls]
          puts "      content=#{r[:content_head].inspect}" if !r[:has_tool_calls] && r[:content_head] && !r[:content_head].empty?
        elsif r[:ok]
          tc = r[:tool_call_present] ? ' TOOL✓' : ' TOOL✗'
          puts format('  OK  %-32s class=%s%s', name, r[:content_class], tc)
          puts "      tool_calls=#{r[:tool_calls].inspect[0, 200]}" if r[:tool_call_present]
        else
          puts format('  ERR %-32s %s: %s', name, r[:class], r[:message].to_s[0, 80])
        end
      end
    end
  end
end
