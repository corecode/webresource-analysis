require 'json'
require 'uri'

class Domain
  Fields = {
    :domainId => -1,
    :requestId => nil,
    :url => nil,
    :host => nil,
    :initiator => nil,
    :cached => false,
    :dataLength => 0,
    :encodedDataLength => 0,
    :mimeType => nil,
    :pageType => nil,
    :status => -1,
    :redirect => false,
    :failed => true,
  }

  def initialize(file, id=nil)
    @file = file
    @data = File.readlines(file)
    @requests = Hash.new{|h,k| h[k] = Fields.merge({:domainId => id})}
    @res = []
  end

  def fields
    Fields
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
    @requests.delete_if {|_, r| not r[:url]}
    @res.concat @requests.values
    @requests.clear
    @res
  end

  def process_line(l)
    d = JSON l
    p = d['params']
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
      flush_req res
    when "Network.requestFailed"
      do_request_failed p
    when "Network.loadingFinished"
      do_request_finished p
    end
  end

  def have_req(d)
    @requests.include? d['requestId']
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
    return if url.match(/^(?:about|data|chrome):/)

    rd = req['redirectResponse']
    if rd
      do_response(req, req, rd, true)
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
               })
  end

  def do_request_failed(res)
    update_req(res, {:failed => true})
    flush_req(res)
  end

  def do_request_finished(res)
    return if !have_req(res) || !get_req(res)[:url]
    update_req(res, {:failed => false})
    flush_req(res)
  end

  def do_response(req, par=req, resp=par['response'], redirect=false)
    return if resp['url'].match(/^(?:about|data|chrome):/)
    h = {
      :status => resp['status'],
      :redirect => redirect,
      :failed => false,
      :mimeType => resp['mimeType'],
      :pageType => par['type'],
    }
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
