#!/usr/bin/env ruby

if ARGV.empty?
puts "usage: #{File.basename(__FILE__)} host [update interval] [ttl] [keyfile]" # change to $0 if files are split
exit # prevents long running requests stalling
end

require "net/http"
require "time"
require "openssl"
require "base64"
require "nokogiri"

@api_path = "https://route53.amazonaws.com/2012-02-29" # maybe a constant instead?
@hostname = ARGV[0]
@upd_int = 30
@upd_int = ARGV[1].to_i unless ARGV[1].to_s.empty?

def get_info(type)
  file_name = 'aws.key'
  file_name = ARGV[3] unless ARGV[3].to_s.empty?
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

def set_date_auth
  @request['Date'] = Time.new.rfc822
  @request['X-Amzn-Authorization'] = "AWS3-HTTPS AWSAccessKeyId=#{get_info('access')},Algorithm=HmacSHA256,Signature=#{gensig}"
end

def build_xml
  ttl = '60'
  ttl = ARGV[2] unless ARGV[2].to_s.empty?
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

  set_date_auth
  send_request

  xml = Nokogiri::XML(send_request)
  @change_id = xml.css("Id").to_s.sub(/<Id>/,"").sub(/<\/Id>/,"") # ugly. unfortunatley xml.xpath("//Id()") refuses to work (is it html only?)
end

def status
  @uri = URI(@api_path+"#{@change_id}")
  @request = Net::HTTP::Get.new(@uri.path)

  set_date_auth
  send_request

  xml = Nokogiri::XML(send_request)
  return xml.css("Status").to_s.sub(/<Status>/,"").sub(/<\/Status>/,"")
end

def fetch_aws_ip
  @uri = URI(@api_path+"/hostedzone/#{get_info('hostedzone')}/rrset")
  @uri.query = URI.encode_www_form({name: @hostname, type: "A", maxitems: "1"})
  @request = Net::HTTP::Get.new(@uri.request_uri)

  set_date_auth
  send_request

  xml = Nokogiri::XML(send_request)
  @old_ip = xml.css("Value").to_s.sub(/<Value>/,"").sub(/<\/Value>/,"")
end


# broke everything while prettying this up and had to revert

# fetch_aws_ip
# awsip = @old_ip

# loop do
#   currentip = Net::HTTP.get('icanhazip.com', '/')
#   if currentip != awsip
#     update

#     while status == 'PENDING'
#       puts "Pending..."
#       sleep 30
#     end
#     puts "Done! Status #{status}. Will check again in #{@upd_int} mins"
#     awsip = currentip
#   end
#   sleep @upd_int*60
# end