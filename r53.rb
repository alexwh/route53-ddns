#!/usr/bin/env ruby
require "net/http"
require "time"
require "openssl"
require "base64"
require "nokogiri"

@api_path = "https://route53.amazonaws.com/2012-02-29" # maybe a constant instead?
@hostname = ARGV[0]

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

def gensig
  time = Time.new.rfc822
  digested_data = OpenSSL::HMAC.digest(OpenSSL::Digest::Digest.new('sha256'), get_info('secret'), time)
  return Base64::encode64(digested_data).chomp
end

def send_request
  Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https') do |http|
    response = http.request(@request)
    return response.body
  end
end

def get_date_auth
  @request['Date'] = Time.new.rfc822
  @request['X-Amzn-Authorization'] = "AWS3-HTTPS AWSAccessKeyId=#{get_info('access')},Algorithm=HmacSHA256,Signature=#{gensig}"
end

def build_xml
  ttl = '60'
  ttl = ARGV[1] unless ARGV[1].to_s.empty?
  pubip = Net::HTTP.get('icanhazip.com', '/') # ifconfig.me was very slow - switched

  builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
    xml.ChangeResourceRecordSetsRequest('xmlns' => 'https://route53.amazonaws.com/doc/2012-02-29/') {
      xml.ChangeBatch {
        xml.Comment "Automatic DNS update for #{@hostname} from #{@old_ip} to #{pubip}"
        xml.Changes {
          xml.Change {
            xml.Action "DELETE"
            xml.ResourceRecordSet {
              xml.Name @hostname
              xml.Type "A"
              xml.TTL ttl

              xml.ResourceRecords {
                xml.ResourceRecord {
                  xml.Value @old_ip
                }
              }
            }
          }
          xml.Change {
            xml.Action "CREATE"
            xml.ResourceRecordSet {
              xml.Name @hostname
              xml.Type "A"
              xml.TTL ttl

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

def update
  @uri = URI("#{@api_path}/hostedzone/#{get_info('hostedzone')}/rrset")

  @request = Net::HTTP::Post.new(@uri.path)
  @request.body = build_xml
  @request.content_type = 'text/xml'

  get_date_auth

  send_request

  xml = Nokogiri::XML(send_request)
  @change_id = xml.css("Id").to_s.sub(/<Id>/,"").sub(/<\/Id>/,"") # ugly. unfortunatley xml.xpath("//Id()") refuses to work (is it html only?)
end

def fetch_old_ip
  @uri = URI(@api_path+"/hostedzone/#{get_info('hostedzone')}/rrset")
  params = {name: @hostname, type: "A", maxitems: "1"}
  @uri.query = URI.encode_www_form(params)
  @request = Net::HTTP::Get.new(@uri.request_uri)

  get_date_auth

  send_request

  xml = Nokogiri::XML(send_request)
  @old_ip = xml.css("Value").to_s.sub(/<Value>/,"").sub(/<\/Value>/,"")
end

def status
  @uri = URI(@api_path+"#{@change_id}")
  @request = Net::HTTP::Get.new(@uri.path)

  get_date_auth

  send_request

  xml = Nokogiri::XML(send_request)
  return xml.css("Status").to_s.sub(/<Status>/,"").sub(/<\/Status>/,"")
end

puts "usage: #{$0} host [ttl] [keyfile]" if ARGV.empty?

fetch_old_ip
update

while status == 'PENDING'
  puts status
  sleep 15
end

puts "Done!" if status == 'INSYNC'