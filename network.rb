require 'json'
require 'uri'

class Domain
  def initialize(file, domainid)
    @data = File.readlines(file)
    @domainid = domainid
  end

  def process
    @data.each do |l|
      r = process_line(l)
      puts r if r
    end
  end

  def process_line(l)
    d = JSON l
    require 'pp'
    p = d['result']
    return unless p
    case d['method']
    when "Network.requestWillBeSent"
      r = p['redirectResponse']
      s = ""
      if r
        s = process_response(p, r, true) + "\n"
      end
      s + process_initiator(p['request']['url'], p)
    when "Network.responseReceived"
      process_response p, p['response']
    when "Network.dataReceived"
      process_data p
    when "Network.requestServedFromMemoryCache"
      process_initiator p['resource']['url'], p, true
    end
  end

  def process_initiator(url, d, from_cache=false)
    initiator = case d['initiator']['type']
                when 'script'
                  2
                when 'parser'
                  0
                else
                  1
                end
    h = {
      :domainId => @domainid,
      :requestId => d['requestId'],
      :timestamp => d['timestamp'],
      :url => url,
      :initiator => initiator,
      :fromCache => from_cache ? 1 : 0,
    }
    do_insert('initiator', h)
  end

  def process_response(r, d, did_redirect=false)
    host = URI.parse(URI.encode(d['url']))
    host = "#{host.host}:#{host.port}"
    h = {
      :domainId => @domainid,
      :requestId => r['requestId'],
      :timestamp => r['timestamp'],
      :host => host,
      :connectionId => d['connectionId'],
      :connectionReused => d['connectionReused'] == "true" ? 1 : 0,
      :mimeType => d['mimeType'],
      :status => d['status'],
      :didRedirect => did_redirect ? 1 : 0,
    }
    do_insert('request', h)
  end

  def process_data(d)
    h = {
      :domainId => @domainid,
      :requestId => d['requestId'],
      :timestamp => d['timestamp'],
      :dataLength => d['dataLength'],
      :encodedDataLength => d['encodedDataLength'],
    }
    do_insert('transfer', h)
  end

  def do_insert(table, data)
    'INSERT INTO %s (%s) VALUES (%s);' %
      [
       table,
       data.keys.join(', '),
       data.values.map { |d|
         case d
         when Numeric
           d.to_s
         when nil
           'NULL'
         else
           "\"#{d}\""
         end
       }.join(', ')
      ]
  end
end

if $0 == __FILE__
  id = 0
  ARGV.each do |f|
    id += 1
    d = Domain.new(f, id)
    d.process
  end
end
