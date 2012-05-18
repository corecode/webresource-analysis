require 'json'
require 'uri'

class Domain
  def initialize(file, id)
    @file = file
    @data = File.readlines(file)
    @domainid = id
    @requests = Hash.new{|h,k| h[k] = {:domainId => @domainid}}
    @res = []
  end

  def process
    @data.each_with_index do |l, i|
      begin
        process_line(l)
      rescue Exception => e
        $stderr.puts "Error processing #{@file}:#{i+1}: #{l}"
        $stderr.puts e
        $stderr.puts e.backtrace
      end
    end
    @res.concat @requests.values
    @requests.clear
    @res
  end

  def process_line(l)
    d = JSON l
    p = d['result']
    return unless p
    case d['method']
    when "Network.requestWillBeSent"
      do_request(p['request']['url'], p)
    when "Network.responseReceived"
      do_response p
    when "Network.dataReceived"
      do_data p
    when "Network.requestServedFromMemoryCache"
      res = p['resource']
      do_request res['url'], p, true
      do_response p, res
    end
  end

  def get_req(d)
    @requests[d['requestId']]
  end

  def update_req(d, h)
    get_req(d).merge!(h)
  end

  def flush_req(d)
    return unless @requests.include? d['requestId']
    @res << get_req(d)
    @requests.delete(d['requestId'])
  end
  
  def do_request(url, req, cached=false)
    rd = req['redirectResponse']
    if rd
      do_response(req, rd, true)
    end

    flush_req(req)

    initiator = req['initiator']['type']
    if !url.match(%r{[^:]+://})
      # some data or about url
      url = url[/^[^:]*/]
    end
    update_req(req,
               {
                 :requestId => req['requestId'],
                 :url => url,
                 :host => host_from_url(url),
                 :initiator => initiator,
                 :cached => cached,
                 :dataLength => 0,
                 :encodedDataLength => 0,
               })
  end

  def do_response(req, resp=nil, redirect=false)
    resp = req['response'] unless resp
    h = {
      :status => resp['status'],
      :redirect => redirect
    }
    mt = resp['mimeType']
    if mt
      h[:mimeType] = mt
    end
    update_req(req, h)
  end

  def do_data(d)
    r = get_req(d)
    r[:dataLength] += d['dataLength']
    r[:encodedDataLength] += d['encodedDataLength']
  end

  def host_from_url(url)
    m = %r{([^:]*?):(//)?([^:/]*)(:\d+)?}.match(url)
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
    host
  end
end
