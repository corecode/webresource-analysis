require 'json'
require 'uri'

class Domain
  def initialize(file, id, printer)
    @domainid = id
    @data = File.readlines(file)
    @printer = printer
  end

  def process
    @data.each do |l|
      process_line(l)
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
      if r
        request(p, r, true) + "\n"
      end
      resource(p['request']['url'], p)
    when "Network.responseReceived"
      request p, p['response']
    when "Network.dataReceived"
      transfer p
    when "Network.requestServedFromMemoryCache"
      resource p['resource']['url'], p, true
    end
  end

  def resource(url, d, from_cache=false)
    initiator = case d['initiator']['type']
                when 'script'
                  2
                when 'parser'
                  0
                else
                  1
                end
    if url.match(%r{[^:]+://})
      url = url.gsub(/[\\"]/, '\\\1')
    else
      # some data or about url
      url = nil
    end
    h = {
      :domainId => @domainid,
      :requestId => d['requestId'],
      :timestamp => d['timestamp'],
      :url => url,
      :initiator => initiator,
      :fromCache => from_cache,
    }
    @printer.resource h
  end

  def request(r, d, did_redirect=false)
    uri = d['url']
    m = %r{([^:]*?):(//)?([^:/]*)(:\d+)?}.match(uri)
    if m && m[2]
      host = m[3]
      if m[4]
        host += m[4]
      else
        case m[1]
        when "http"
          host += ":80"
        when "https"
          host += ":443"
        else
          host = m[1] + "://" + m[3]
        end
      end
    else
      host = nil
    end
    h = {
      :domainId => @domainid,
      :requestId => r['requestId'],
      :timestamp => r['timestamp'],
      :host => host,
      :connectionId => d['connectionId'],
      :connectionReused => d['connectionReused'],
      :mimeType => d['mimeType'],
      :status => d['status'],
      :didRedirect => did_redirect,
    }
    @printer.request h
  end

  def transfer(d)
    h = {
      :domainId => @domainid,
      :requestId => d['requestId'],
      :timestamp => d['timestamp'],
      :dataLength => d['dataLength'],
      :encodedDataLength => d['encodedDataLength'],
    }
    @printer.transfer h
  end
end
