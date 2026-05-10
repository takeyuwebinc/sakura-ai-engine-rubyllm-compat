# frozen_string_literal: true

require_relative '../probe_runner'

module Probes
  module EStreaming
    PROMPT = '日本の県庁所在地を 3 つ、改行区切りで挙げて'

    module_function

    def run(model_id = nil)
      model_id ||= ProbeRunner.default_chat_model
      ProbeRunner.configure_ruby_llm
      result = {
        purpose: 'E: streaming の挙動と stream_options.include_usage の受理可否',
        model: model_id,
        scenarios: {}
      }

      result[:scenarios][:raw_stream_no_usage] = scenario_raw_stream(model_id, include_usage: nil)
      result[:scenarios][:raw_stream_include_usage] = scenario_raw_stream(model_id, include_usage: true)
      result[:scenarios][:rubyllm_streaming] = scenario_rubyllm_streaming(model_id)
      result[:scenarios][:rubyllm_streaming_with_schema] = scenario_rubyllm_streaming_with_schema(model_id)

      path = ProbeRunner.record('e_streaming', model_id, result)
      puts "Saved: #{path}"
      print_summary(result)
    end

    def scenario_raw_stream(model_id, include_usage:)
      uri = URI.join("#{ProbeRunner.api_base}/", 'chat/completions')
      payload = {
        model: model_id,
        messages: [{ role: 'user', content: PROMPT }],
        temperature: 0,
        max_tokens: 128,
        stream: true
      }
      payload[:stream_options] = { include_usage: true } if include_usage

      req = Net::HTTP::Post.new(uri)
      req['Authorization'] = "Bearer #{ProbeRunner.api_key}"
      req['Content-Type'] = 'application/json'
      req['Accept'] = 'text/event-stream'
      req.body = JSON.generate(payload).force_encoding(Encoding::UTF_8)

      chunks = []
      usage_chunk_seen = false
      first_status = nil
      err_body = nil
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 60) do |http|
        http.request(req) do |resp|
          first_status = resp.code.to_i
          if first_status != 200
            err_body = resp.body.to_s[0, 500]
            next
          end
          buffer = String.new(encoding: 'UTF-8')
          resp.read_body do |segment|
            buffer << segment
            while (line_end = buffer.index("\n"))
              line = buffer.slice!(0..line_end)
              line = line.chomp
              next unless line.start_with?('data:')

              data = line.sub(/^data:\s*/, '')
              break if data == '[DONE]'

              parsed = ProbeRunner.safe_json(data)
              next unless parsed

              chunks << parsed
              usage_chunk_seen = true if parsed['usage']
            end
          end
        end
      end

      content_assembled = chunks.map { |c| c.dig('choices', 0, 'delta', 'content') }.compact.join
      finish_reason = chunks.reverse.find { |c| c.dig('choices', 0, 'finish_reason') }&.dig('choices', 0, 'finish_reason')
      usage = chunks.find { |c| c['usage'] }&.dig('usage')

      {
        status: first_status,
        chunk_count: chunks.size,
        content_assembled: content_assembled[0, 200],
        finish_reason: finish_reason,
        usage_chunk_seen: usage_chunk_seen,
        usage: usage,
        error_body: err_body
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def scenario_rubyllm_streaming(model_id)
      chat = ProbeRunner.chat(model: model_id)
      collected = []
      chunks_seen = 0
      msg = chat.with_temperature(0).ask(PROMPT) do |chunk|
        chunks_seen += 1
        collected << chunk.content if chunk.respond_to?(:content) && chunk.content
      end
      {
        ok: true,
        chunks_seen: chunks_seen,
        collected_head: collected.join[0, 200],
        final_content_head: msg.content.to_s[0, 200],
        input_tokens: msg.input_tokens,
        output_tokens: msg.output_tokens
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    # 構造化出力 + streaming の組み合わせ（plan.md §3.2.E）
    def scenario_rubyllm_streaming_with_schema(model_id)
      require 'ruby_llm/schema'
      schema_class = Class.new(RubyLLM::Schema) do
        string :answer
      end

      chat = ProbeRunner.chat(model: model_id)
      chunks_seen = 0
      msg = chat.with_schema(schema_class).with_temperature(0).ask('answer に "ok" とだけ入れた JSON を返して') do |_chunk|
        chunks_seen += 1
      end
      {
        ok: true,
        chunks_seen: chunks_seen,
        content: msg.content,
        content_class: msg.content.class.name,
        is_hash: msg.content.is_a?(Hash)
      }
    rescue StandardError => e
      ProbeRunner.summarize_error(e)
    end

    def print_summary(result)
      puts "\n=== Summary (model: #{result[:model]}) ==="
      result[:scenarios].each do |name, r|
        if r[:status]
          tag = r[:status] == 200 ? 'OK ' : 'NG '
          usage = r[:usage_chunk_seen] ? ' USAGE✓' : ' USAGE✗'
          fr = r[:finish_reason] ? " fr=#{r[:finish_reason]}" : ''
          puts format('  %s %-32s HTTP %d chunks=%d%s%s', tag, name, r[:status], r[:chunk_count], usage, fr)
          puts "      content=#{r[:content_assembled].inspect[0, 200]}" if r[:content_assembled]
          puts "      err=#{r[:error_body]}" if r[:error_body]
        elsif r[:ok]
          puts format('  OK  %-32s chunks=%d class=%s', name, r[:chunks_seen], r[:content_class] || 'String')
          puts "      content=#{(r[:final_content_head] || r[:content].to_s)[0, 200].inspect}"
        else
          puts format('  ERR %-32s %s: %s', name, r[:class], r[:message].to_s[0, 80])
        end
      end
    end
  end
end
