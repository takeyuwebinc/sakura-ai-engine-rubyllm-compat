# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'
require 'net/http'
require 'uri'
require 'dotenv/load'
require 'ruby_llm'

module ProbeRunner
  RESULT_DIR = File.expand_path('../tmp/probe_results', __dir__)

  PROVIDERS = {
    sakura: {
      api_base: 'https://api.ai.sakura.ad.jp/v1',
      api_base_env: nil,
      env_key: 'SAKURA_AI_ACCOUNT_KEY',
      default_chat_model: 'gpt-oss-120b',
      default_vision_model: 'preview/Qwen3-VL-30B-A3B-Instruct',
      force_openai_use_system_role: true
    },
    openai: {
      api_base: 'https://api.openai.com/v1',
      api_base_env: 'OPENAI_API_BASE',
      env_key: 'OPENAI_API_KEY',
      default_chat_model: 'gpt-4o-mini',
      default_vision_model: 'gpt-4o-mini',
      force_openai_use_system_role: false
    }
  }.freeze

  module_function

  def current_provider
    @current_provider ||= begin
      name = (ENV['PROBE_PROVIDER'] || 'sakura').to_sym
      unless PROVIDERS.key?(name)
        abort "Unknown provider: #{name}. Available: #{PROVIDERS.keys.join(', ')}"
      end
      name
    end
  end

  def set_provider(name)
    name = name.to_sym
    unless PROVIDERS.key?(name)
      abort "Unknown provider: #{name}. Available: #{PROVIDERS.keys.join(', ')}"
    end
    @current_provider = name
  end

  def provider_config
    PROVIDERS.fetch(current_provider)
  end

  def api_base
    env_name = provider_config[:api_base_env]
    if env_name && ENV[env_name] && !ENV[env_name].to_s.empty?
      ENV[env_name]
    else
      provider_config[:api_base]
    end
  end

  def env_key
    provider_config[:env_key]
  end

  def api_key
    value = ENV[env_key]
    if value.nil? || value.empty?
      abort "ENV[#{env_key}] is not set. See .env (provider=#{current_provider})"
    end
    value
  end

  def default_chat_model
    provider_config[:default_chat_model]
  end

  def default_vision_model
    provider_config[:default_vision_model]
  end

  def models_module
    case current_provider
    when :sakura
      require_relative 'sakura_models'
      SakuraModels
    when :openai
      require_relative 'openai_models'
      OpenAIModels
    end
  end

  def configure_ruby_llm
    base = api_base
    key = api_key
    cfg = provider_config
    RubyLLM.configure do |c|
      c.openai_api_key  = key
      c.openai_api_base = base
      c.openai_use_system_role = true if cfg[:force_openai_use_system_role]
      c.log_level = :warn
    end
  end

  def chat(model:, **opts)
    RubyLLM.chat(
      model: model,
      provider: :openai,
      assume_model_exists: true,
      **opts
    )
  end

  def raw_post(path:, payload:, extra_headers: {})
    uri = URI.join("#{api_base}/", path.sub(%r{^/}, ''))
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{api_key}"
    req['Content-Type'] = 'application/json'
    req['Accept'] = 'application/json'
    extra_headers.each { |k, v| req[k] = v }
    req.body = JSON.generate(payload).force_encoding(Encoding::UTF_8)
    started = Time.now
    resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 120) { |http| http.request(req) }
    {
      url: uri.to_s,
      request_payload: payload,
      status: resp.code.to_i,
      headers: resp.to_hash,
      body_raw: resp.body,
      body_parsed: safe_json(resp.body),
      duration_ms: ((Time.now - started) * 1000).round
    }
  end

  def safe_json(str)
    return nil if str.nil? || str.empty?

    JSON.parse(str)
  rescue JSON::ParserError
    nil
  end

  def record(probe_name, model_id, payload)
    FileUtils.mkdir_p(RESULT_DIR)
    safe_model = model_id.to_s.gsub(%r{[^A-Za-z0-9._\-]}, '_')
    provider = current_provider.to_s
    filename = "#{provider}__#{probe_name}__#{safe_model}.json"
    path = File.join(RESULT_DIR, filename)
    File.write(path, JSON.pretty_generate(
      {
        provider: provider,
        api_base: api_base,
        probe: probe_name,
        model: model_id,
        recorded_at: Time.now.iso8601,
        ruby_llm_version: defined?(RubyLLM::VERSION) ? RubyLLM::VERSION : nil,
        ruby_version: RUBY_VERSION
      }.merge(payload)
    ))
    path
  end

  def summarize_error(err)
    {
      class: err.class.name,
      message: err.message,
      backtrace_head: Array(err.backtrace).first(3)
    }
  end
end
