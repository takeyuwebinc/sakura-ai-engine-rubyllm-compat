# frozen_string_literal: true

require_relative '../probe_runner'
require 'ruby_llm/schema'

module Probes
  module CSchema
    # OpenAI API 互換性検証として有効な「中立」プロンプト。
    # 出力形式（JSON / フィールド名）を文章で指示しないことで、
    # response_format / json_schema の効果を切り分ける。
    NEUTRAL_PROMPT = '東京の架空の天気を返して'

    SCHEMA_DEF = {
      type: 'object',
      properties: {
        temperature_celsius: { type: 'number', description: '摂氏気温' },
        condition: { type: 'string', enum: %w[sunny cloudy rainy snowy], description: '天気' }
      },
      required: %w[temperature_celsius condition],
      additionalProperties: false
    }.freeze

    class WeatherSchema < RubyLLM::Schema
      number :temperature_celsius, description: '摂氏気温'
      string :condition, enum: %w[sunny cloudy rainy snowy], description: '天気'
    end

    module_function

    def run(model_id = nil)
      model_id ||= ProbeRunner.default_chat_model
      ProbeRunner.configure_ruby_llm
      result = {
        purpose: 'C: 構造化出力（response_format / json_schema）の OpenAI 互換性検証',
        prompt: NEUTRAL_PROMPT,
        prompt_policy: 'neutral - プロンプトで JSON 出力を指示しない。' \
                       'JSON が返るなら response_format が効いた証拠と判定する',
        model: model_id,
        scenarios: {}
      }

      # Step 0: RubyLLM が OpenAI 仕様の response_format を実際に送信しているかを webmock で確認。
      # Sakura ゲートウェイには到達せず、純粋にクライアント側 payload 形状の検証
      result[:scenarios][:rubyllm_payload_shape] = scenario_payload_shape(model_id)

      # Step 1+: 中立プロンプトでの実機検証
      result[:scenarios][:raw_no_format] = scenario_raw_no_format(model_id)
      result[:scenarios][:raw_json_object] = scenario_raw_json_object(model_id)
      result[:scenarios][:raw_json_schema_strict] = scenario_raw_json_schema(model_id, strict: true)
      result[:scenarios][:raw_json_schema_loose] = scenario_raw_json_schema(model_id, strict: false)
      result[:scenarios][:rubyllm_with_schema] = scenario_rubyllm_with_schema(model_id)
      result[:scenarios][:rubyllm_schema_invalid_input] = scenario_rubyllm_schema_invalid_input(model_id)

      result[:compat_verdict] = build_verdict(result[:scenarios])

      path = ProbeRunner.record('c_schema', model_id, result)
      puts "Saved: #{path}"
      print_summary(result)
    end

    def scenario_payload_shape(model_id)
      require 'webmock'
      WebMock.enable!
      WebMock.disable_net_connect!
      captured = nil
      stub_pattern = Regexp.new("#{Regexp.escape(ProbeRunner.api_base)}/chat/completions")
      WebMock.stub_request(:post, stub_pattern)
             .to_return do |req|
        captured = JSON.parse(req.body)
        {
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate(
            id: 'fake', object: 'chat.completion', created: 0, model: model_id,
            choices: [{ index: 0,
                        message: { role: 'assistant',
                                   content: '{"temperature_celsius":22,"condition":"sunny"}' },
                        finish_reason: 'stop' }],
            usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
          )
        }
      end
      ProbeRunner.chat(model: model_id)
                 .with_schema(WeatherSchema)
                 .with_temperature(0)
                 .ask(NEUTRAL_PROMPT)

      rf = captured && captured['response_format']
      {
        ok: !captured.nil?,
        captured_payload_keys: captured&.keys,
        response_format: rf,
        openai_spec_compliant: openai_spec_compliant?(rf),
        note: 'RubyLLM が送出する payload 形状の検証。Sakura ゲートウェイには到達しない'
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    ensure
      if defined?(WebMock)
        WebMock.reset!
        WebMock.disable!
      end
    end

    def openai_spec_compliant?(rf)
      return false unless rf.is_a?(Hash)
      return false unless rf['type'] == 'json_schema'

      js = rf['json_schema']
      return false unless js.is_a?(Hash)
      return false unless js['name'].is_a?(String) && !js['name'].empty?
      return false unless js['schema'].is_a?(Hash)

      true
    end

    def scenario_raw_no_format(model_id)
      r = ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [{ role: 'user', content: NEUTRAL_PROMPT }],
          temperature: 0,
          max_tokens: 1024
        }
      )
      summarize(r)
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_raw_json_object(model_id)
      r = ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [{ role: 'user', content: NEUTRAL_PROMPT }],
          temperature: 0,
          max_tokens: 1024,
          response_format: { type: 'json_object' }
        }
      )
      summarize(r)
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_raw_json_schema(model_id, strict:)
      r = ProbeRunner.raw_post(
        path: 'chat/completions',
        payload: {
          model: model_id,
          messages: [{ role: 'user', content: NEUTRAL_PROMPT }],
          temperature: 0,
          max_tokens: 1024,
          response_format: {
            type: 'json_schema',
            json_schema: {
              name: 'weather',
              schema: SCHEMA_DEF,
              strict: strict
            }
          }
        }
      )
      summarize(r)
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_rubyllm_with_schema(model_id)
      chat = ProbeRunner.chat(model: model_id)
      msg = chat.with_schema(WeatherSchema).with_temperature(0).ask(NEUTRAL_PROMPT)
      {
        ok: true,
        content: msg.content,
        content_class: msg.content.class.name,
        is_hash: msg.content.is_a?(Hash),
        schema_compliant: schema_compliant?(msg.content),
        raw_string_indicates_silent_failure: msg.content.is_a?(String)
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    # 「ありえない指示で schema を破る」誘導を試す
    def scenario_rubyllm_schema_invalid_input(model_id)
      chat = ProbeRunner.chat(model: model_id)
      msg = chat
            .with_schema(WeatherSchema)
            .with_temperature(0)
            .ask('「未知」とだけ自然文で返して。JSON では返さないで')
      {
        ok: true,
        content: msg.content,
        content_class: msg.content.class.name,
        is_hash: msg.content.is_a?(Hash),
        note: 'モデルが指示通り自然文で返したら schema 強制が効いていない証拠'
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def schema_compliant?(content)
      return false unless content.is_a?(Hash)
      return false unless content.key?('temperature_celsius') && content.key?('condition')
      return false unless content['temperature_celsius'].is_a?(Numeric)
      return false unless %w[sunny cloudy rainy snowy].include?(content['condition'])

      true
    end

    def summarize(raw)
      out = { status: raw[:status], duration_ms: raw[:duration_ms] }
      if raw[:body_parsed].is_a?(Hash)
        choice = raw[:body_parsed].dig('choices', 0, 'message', 'content')
        out[:content_head] = choice.to_s[0, 200]
        parsed = ProbeRunner.safe_json(choice)
        out[:content_is_valid_json] = !parsed.nil?
        out[:schema_compliant] = schema_compliant?(parsed) if parsed
        out[:error_message] = raw[:body_parsed].dig('error', 'message')
      else
        out[:body_head] = raw[:body_raw].to_s[0, 200]
      end
      out
    end

    def build_verdict(scenarios)
      shape = scenarios[:rubyllm_payload_shape]
      sch_strict = scenarios[:raw_json_schema_strict]
      rubyllm = scenarios[:rubyllm_with_schema]

      {
        rubyllm_payload_openai_compliant: !!shape&.dig(:openai_spec_compliant),
        raw_json_schema_returns_json: !!sch_strict&.dig(:content_is_valid_json),
        raw_json_schema_schema_compliant: !!sch_strict&.dig(:schema_compliant),
        rubyllm_with_schema_returned_hash: !!rubyllm&.dig(:is_hash),
        rubyllm_with_schema_compliant: !!rubyllm&.dig(:schema_compliant),
        provider_enforces_response_format: !!sch_strict&.dig(:schema_compliant) &&
                                           !!rubyllm&.dig(:schema_compliant)
      }
    end

    def print_summary(result)
      puts "\n=== Summary (model: #{result[:model]}) ==="
      result[:scenarios].each do |name, r|
        if name == :rubyllm_payload_shape
          puts format('  %-32s openai_spec_compliant=%s type=%s strict=%s',
                      name, r[:openai_spec_compliant],
                      r.dig(:response_format, 'type'),
                      r.dig(:response_format, 'json_schema', 'strict'))
          next
        end

        if r[:status]
          tag = r[:status] == 200 ? 'OK ' : 'NG '
          json_tag = r[:content_is_valid_json] == false ? ' JSON✗' : ''
          schema_tag = case r[:schema_compliant]
                       when true then ' SCHEMA✓'
                       when false then ' SCHEMA✗'
                       else ''
                       end
          err = r[:error_message] ? " err=#{r[:error_message].to_s[0, 80]}" : ''
          puts format('  %s %-32s HTTP %d%s%s%s', tag, name, r[:status], json_tag, schema_tag, err)
        elsif r[:ok]
          schema_tag = r[:schema_compliant] ? ' SCHEMA✓' : ' SCHEMA✗'
          puts format('  OK  %-32s class=%s%s', name, r[:content_class], schema_tag)
          puts "      content=#{r[:content].inspect[0, 200]}"
        else
          puts format('  ERR %-32s %s: %s', name, r[:class], r[:message].to_s[0, 80])
        end
      end

      v = result[:compat_verdict]
      puts "\n--- compat verdict ---"
      v.each { |k, val| puts format('  %-40s = %s', k, val) }
    end
  end
end
