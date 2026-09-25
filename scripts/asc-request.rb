require 'spaceship'
require 'dotenv'
require 'json'
require 'net/http'

# Uses the existing Fastlane key without printing credentials.
Dir.chdir(File.expand_path('..', __dir__))
Dotenv.load('fastlane/.env')
$asc_token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch('ASC_KEY_ID'), issuer_id: ENV.fetch('ASC_ISSUER_ID'),
  filepath: ENV.fetch('ASC_KEY_PATH')
).text
def asc_request(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = Net::HTTP.const_get(method.capitalize).new(uri)
  request['Authorization'] = "Bearer #{$asc_token}"
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 60) { |http| http.request(request) }
  raise "App Store Connect #{response.code}: #{response.body}" unless response.code.to_i < 300
  response.body.to_s.empty? ? {} : JSON.parse(response.body)
end

if $PROGRAM_NAME == __FILE__
  method, path, body_path = ARGV
  abort 'Usage: ruby scripts/asc-request.rb GET /v1/... [json-file]' unless method && path
  puts JSON.pretty_generate(asc_request(method, path, body_path && JSON.parse(File.read(body_path))))
end
