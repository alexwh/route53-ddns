#!/usr/bin/env ruby
require 'net/http'
require 'time'
require 'openssl'
require 'base64'

def getip
  return Net::HTTP.get('ifconfig.me', '/ip')
end

def get_info(type)
  file_name = 'acc.info'
  info = Array.new
  f = File.new(file_name, 'r')
  f.read.each_line {|line| info << line.chomp}
  f.close

  return info[0] if type == 'secret' # your AWS secret
  return info[1] if type == 'access' # your AWS access key ID
  return info[2] if type == 'hostedzone' # your hosted zone ID
  return info[3] if type == 'basehost' # your base domain, prepended with a dot (e.g. .example.com) @TODO: change that
end

@hostname = ARGV[0]
@basehost = get_info('basehost')

# @TODO: finish formatting of ip to delete

@xml = "<?xml version='1.0' encoding='UTF-8'?>
<ChangeResourceRecordSetsRequest xmlns='https://route53.amazonaws.com/doc/2012-02-29/'>
   <ChangeBatch>
      <Comment>
         Automatic DNS update for #{@hostname} from to #{getip}
      </Comment>
      <Changes>
          <Change>
              <Action>DELETE</Action>
              <ResourceRecordSet>
                 <Name>#{@hostname}#{@basehost}</Name>
                 <Type>A</Type>
                 <TTL>60</TTL>
                 <ResourceRecords>
                    <ResourceRecord>
                       <Value>xxx.xxx.xxx.xxx</Value>
                    </ResourceRecord>
                 </ResourceRecords>
              </ResourceRecordSet>
           </Change>
           <Change>
            <Action>CREATE</Action>
            <ResourceRecordSet>
               <Name>#{@hostname}#{@basehost}</Name>
               <Type>A</Type>
               <TTL>60</TTL>
               <ResourceRecords>
                  <ResourceRecord>
                     <Value>#{getip}</Value>
                  </ResourceRecord>
               </ResourceRecords>
            </ResourceRecordSet>
         </Change>
      </Changes>
   </ChangeBatch>
</ChangeResourceRecordSetsRequest>"

def request
  baseurl = 'https://route53.amazonaws.com'
  apipath = "/2012-02-29/hostedzone/#{get_info('hostedzone')}/"
  uri = URI(baseurl+apipath+'rrset') # seems dirty

  digest = OpenSSL::Digest::Digest.new('sha256')
  time_data = Time.new.rfc822 # declared in var in case it takes >1 sec
  digested_data = OpenSSL::HMAC.digest(digest, get_info('secret'), time_data)
  signature = Base64::encode64(digested_data).chomp

  request = Net::HTTP::Post.new(uri.path)
  request.body = @xml
  request.content_type = 'text/xml'

  request['Date'] = time_data
  request['X-Amzn-Authorization'] = "AWS3-HTTPS AWSAccessKeyId=#{get_info('access')},Algorithm=Hmac#{digest.name},Signature=#{signature}"


  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    response = http.request(request)
    return response.body
  end
end

# puts request

puts "usage: #{$0} host (to be prepended to #{@basehost})" if ARGV.empty? # @TODO: stop this from being slow as shit
