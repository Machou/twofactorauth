#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'parallel'

# Fetch created/modified files in entries/**
diff = `git diff --name-only --diff-filter=AM origin/master...HEAD entries/`.split("\n")

@headers = {
  'User-Agent' => "2factorauth/URLValidator (Ruby/#{RUBY_VERSION}; +https://2fa.directory/bot)",
  'From' => 'https://2fa.directory/'
}

# Check if the supplied URL works
# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/MethodLength
def check_url(path, url, res = nil)
  depth = 0
  loop do
    depth += 1
    raise('Too many redirections') if depth > 5

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 5
    http.read_timeout = 5
    res = http.request_get(uri.request_uri)

    break unless res.is_a? Net::HTTPRedirection

    url = URI(res['location']).is_a?(URI::HTTP) ? res['location'] : "#{url.scheme}://#{url.host}#{res['location']}"
  end

  puts "::warning file=#{path}:: Unexpected response from #{url} (#{res.code})" unless res.is_a? Net::HTTPSuccess
rescue StandardError => e
  puts "::warning file=#{path}:: Unable to reach #{url}"
  puts "::debug:: #{e.message}" unless e.instance_of?(TypeError)
end
# rubocop:enable Metrics/AbcSize
# rubocop:enable Metrics/MethodLength

Parallel.each(diff, progress: 'Validating URLs') do |path|
  entry = JSON.parse(File.read(path)).values[0]

  # Process the url,domain & additional-domains
  check_url(path, (entry.key?('url') ? entry['url'] : "https://#{entry['domain']}/"))
  entry['additional-domains']&.each { |domain| check_url(path, "https://#{domain}/") }

  # Process documentation and recovery URLs
  check_url(path, entry['documentation']) if entry.key? 'documentation'
  check_url(path, entry['recovery']) if entry.key? 'recovery'
end
