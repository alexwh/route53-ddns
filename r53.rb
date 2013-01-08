#!/usr/bin/env ruby
require "net/http"
require "time"
require "openssl"
require "base64"
require "nokogiri"

@apipath = "https://route53.amazonaws.com/2012-02-29/" # maybe a constant instead?

def get_info(type)
  file_name = 'aws.key'
  file_name = ARGV[2] unless ARGV[2].to_s.empty?
  info = Array.new
  f = File.new(file_name)
  f.read.each_line {|line| info << line.chomp}
  f.close

  return info[0] if type == 'secret'
  return info[1] if type == 'access'
  return info[2] if type == 'hostedzone'
end

def build_xml
  hostname = ARGV[0]
  ttl = '60'
  ttl = ARGV[1] unless ARGV[1].to_s.empty?
  pubip = Net::HTTP.get('icanhazip.com', '/') # ifconfig.me was very slow - switched

  builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
    xml.ChangeResourceRecordSetsRequest('xmlns' => 'https://route53.amazonaws.com/doc/2012-02-29/') {
      xml.ChangeBatch {
        xml.Comment "Automatic DNS update for #{hostname} from **fill previous ip** to #{pubip}"
        xml.Changes {
          xml.Change {
            xml.Action "DELETE"
            xml.ResourceRecordSet {
              xml.Name hostname
              xml.Type "A"
              xml.TTL ttl

              xml.ResourceRecords {
                xml.ResourceRecord {
                  xml.Value fetch
                }
              }
            }
          }
          xml.Change {
            xml.Action "CREATE"
            xml.ResourceRecordSet {
              xml.Name hostname
              xml.Type "A"
              xml.TTL "60"

              xml.ResourceRecords {
                xml.ResourceRecord {
                  xml.Value pubip
                }
              }
            }
          }
        }
      }
    }
  end
  return builder.to_xml
end

def gensig
  @digest = OpenSSL::Digest::Digest.new('sha256')
  @time_data = Time.new.rfc822 # declared in var in case it takes >1 sec
  digested_data = OpenSSL::HMAC.digest(digest, get_info('secret'), time_data)
  return Base64::encode64(digested_data).chomp
end

def request
  Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https') do |http|
    response = http.request(request)
    return response.body
  end
end

def update
  action = "hostedzone/#{get_info('hostedzone')}/rrset"
  @uri = URI(@apipath+action) # seems dirty - some sort of concat method instead?

  request = Net::HTTP::Post.new(uri.path)
  request.body = build_xml
  request.content_type = 'text/xml'

  request['Date'] = @time_data
  request['X-Amzn-Authorization'] = "AWS3-HTTPS AWSAccessKeyId=#{get_info('access')},Algorithm=Hmac#{@digest.name},Signature=#{gensig}"
end

def fetch
  action = "hostedzone/#{get_info('hostedzone')}/rrset"
  @uri = URI(@apipath+action)

  request
end

def status
  action = "change/#{@changeid}"
  @uri = URI(@apipath+action)

  request
end

puts fetch

puts "usage: #{$0} host [ttl] [keyfile]" if ARGV.empty?