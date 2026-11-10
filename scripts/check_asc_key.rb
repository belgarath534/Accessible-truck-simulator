# Tries every App Store Connect API key the workflow collected and keeps the first one Apple accepts.
# Talks to Apple directly (no fastlane). Prints only Key IDs, status codes and Apple's error messages.
require "openssl"
require "base64"
require "json"
require "net/http"

def b64(data) = Base64.urlsafe_encode64(data, padding: false)

def make_jwt(key, kid, issuer)
  now = Time.now.to_i
  header = { alg: "ES256", kid: kid, typ: "JWT" }
  payload = { iss: issuer, iat: now, exp: now + 600, aud: "appstoreconnect-v1" }
  signing_input = "#{b64(header.to_json)}.#{b64(payload.to_json)}"
  der = key.sign(OpenSSL::Digest.new("SHA256"), signing_input)
  r, s = OpenSSL::ASN1.decode(der).value.map { |n| n.value.to_s(2).rjust(32, "\0")[-32..] }
  "#{signing_input}.#{b64(r + s)}"
end

def apple_status(token)
  uri = URI("https://api.appstoreconnect.apple.com/v1/bundleIds?limit=1")
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{token}"
  Net::HTTP.start(uri.host, 443, use_ssl: true) { |http| http.request(request) }
end

issuer = (ENV["ASC_ISSUER_ID_PUBLIC"] || ENV.fetch("ASC_ISSUER_ID")).strip
files = Dir[File.join(Dir.home, ".asc", "candidates", "*.p8")].sort
abort "❌ No .p8 keys found. Upload your AuthKey_XXXXXXXXXX.p8 to the ios-certificates repo." if files.empty?

winner = nil
files.each do |path|
  name = File.basename(path)
  kid = name[/\A(?:AuthKey_|secret_)([A-Za-z0-9]+)\.p8\z/, 1]
  unless kid
    puts "⚠️ Skipping #{name}: can't tell its Key ID (name it AuthKey_<KEYID>.p8)"
    next
  end
  begin
    key = OpenSSL::PKey.read(File.read(path))
  rescue OpenSSL::PKey::PKeyError
    puts "❌ #{kid}: the file isn't a valid private key"
    next
  end
  response = apple_status(make_jwt(key, kid, issuer))
  if response.code == "200"
    puts "✅ #{kid}: Apple accepts this key"
    winner = [path, kid]
    break
  else
    detail = ((JSON.parse(response.body)["errors"] || []).first || {})["code"] rescue nil
    puts "❌ #{kid}: Apple rejects it (HTTP #{response.code} #{detail})"
  end
end

abort "❌ Apple rejected every key. Create a new Team key and upload its .p8 to ios-certificates." unless winner

if ENV["GITHUB_ENV"]
  File.write(ENV["GITHUB_ENV"], "ASC_KEY_PATH=#{winner[0]}\nGOOD_KEY_ID=#{winner[1]}\n", mode: "a")
end
