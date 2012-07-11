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
    :blocked => false,
  }

  attr_reader :requests

  def initialize(file, id=nil)
    @file = file
    @data = File.readlines(file)
    @inflight = Hash.new{|h,k| h[k] = Fields.merge({:domainId => id})}
    @inflight_by_url = Hash.new{|h,k| h[k] = []}
    @adblock_inflight = {}
    @requests = []
  end

  def fields
    Fields
  end

  def process!
    @data.each_with_index do |l, i|
      begin
        process_line(l)
      rescue Exception => e
        $stderr.puts "Error processing #{@file}:#{i+1}: #{l}"
        $stderr.puts e
        $stderr.puts e.backtrace
      end
    end
    @inflight.delete_if {|_, r| not r[:url]}
    @requests.concat @inflight.values
    @inflight.clear

    @adblock_inflight.each do |url, actions|
      next if actions.empty?
      # $stderr.puts "uncollected adblock url: #{actions.join(", ")} #{url}"
    end
    
    @requests
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
    when "Console.messageAdded"
      do_console_message p
    end
  end

  def have_req(d)
    @inflight.include? d['requestId']
  end

  def get_req(d)
    @inflight[d['requestId']]
  end

  def update_req(d, h)
    get_req(d).merge!(h)
  end

  def flush_req(d)
    return unless @inflight.include? d['requestId']
    @requests << get_req(d)
    req = @inflight.delete(d['requestId'])
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

    if @adblock_inflight[url] && (blocked = @adblock_inflight[url].shift)
      update_req(req, {:blocked => blocked})
    else
      @inflight_by_url[url] << get_req(req)
    end
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

  def do_console_message(p)
    msg = p['message']['text']
    m = msg.match(/^ABP: (pass|block)ing .*? to: (.+?)$/)
    return unless m

    action = m[1]
    url = m[2]

    blocked = (action == "block")

    reqs = @inflight_by_url[url]

    # because logs are collected asynchronously, the adblock message
    # may appear before or after the request.  Most of the time they
    # seem to appear after, but sometimes they do appear before.  For
    # these cases we need to keep the adblock action around so that we
    # clean up properly in the end.

    if reqs.empty?
      @adblock_inflight[url] ||= []
      @adblock_inflight[url] << blocked
      return
    end

    req = reqs.shift
    req[:blocked] = blocked
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
