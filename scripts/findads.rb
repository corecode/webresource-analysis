$: << File.expand_path('..', $0)

require 'network'
require 'set'

class AdFinder
  attr_accessor :adblock, :vanilla

  class Classify
    attr_accessor :requests, :common, :ads, :ads_depend
    attr_accessor :soft_common, :soft_ads, :soft_ads_depend, :unknown_ads, :unknown
    attr_reader :original_count

    def initialize(dom)
      @requests = dom.requests
      @common = []
      @ads = []
      @ads_depend = []
      @soft_common = []
      @soft_ads = []
      @soft_ads_depend = []
      @unknown_ads = []
      @unknown = []

      # Make sure we don't lose anything on the way.
      @original_count = @requests.length
    end

    def stats
      %w{common ads ads_depend soft_common soft_ads soft_ads_depend unknown_ads unknown}.inject({}) do |h, f|
        h.update({f.to_sym => instance_variable_get('@'+f).length})
      end
    end

    def count
      %w{common ads ads_depend soft_common soft_ads soft_ads_depend unknown_ads unknown}.inject(0) do |s, f|
        s + instance_variable_get('@' + f).length
      end
    end
  end

  def initialize(adblock, vanilla)
    @adblock, @vanilla = Classify.new(adblock), Classify.new(vanilla)
  end

  def split_url(url)
    m = url.match(/^(\w\w*):(?:\/\/)?([^:\/?#&]+)(?::(\d+))?([^?]+)?(\?.*)?$/)
    if not m
      puts "can not split url: #{url}"
    end
    return {
      :scheme => m[1],
      :host => m[2],
      :port => m[3],
      :path => m[4],
      :query => m[5]
    }
  end

  def match_strings(a, b)
    # implement http://www.catalysoft.com/articles/StrikeAMatch.html
    # http://stackoverflow.com/questions/653157/a-better-similarity-ranking-algorithm-for-variable-length-strings

    if !a ^ !b
      # if one is nil and the other isn't, the score is 0
      return 0
    elsif !a && !b
      # if both are nil, full score
      return 1
    elsif a.length < 2 && b.length < 2
      if a == b
        return 1
      else
        return 0
      end
    end
    ap = (0..a.length-2).map{|i| a[i,2]}
    bp = (0..b.length-2).map{|i| b[i,2]}
    union = ap.size + bp.size
    score = 0
    ap.each do |ae|
      bp.each_with_index do |be, bi|
        next unless ae == be
        # same pair, remove from list
        score += 1
        bp.slice! bi
        break
      end
    end

    if union == 0
      return 1
    end

    2.0 * score / union
  end

  def classify
    # These are clearly ads, so take them out first.
    ads, @adblock.requests = @adblock.requests.partition{|r| r[:blocked]}

    # All requests in vanilla that are in ads are of course also ads.
    ad_urls = Set.new(ads.map{|r| r[:url]})
    @vanilla.ads, @vanilla.requests = @vanilla.requests.partition{|r| ad_urls.include? r[:url]}

    # Now we have identified the set of common ads.  The adblock ads
    # that are not common will be either soft_ads or unknown_ads.
    common_ad_urls = Set.new(@vanilla.ads.map{|r| r[:url]})
    @adblock.ads, ads = ads.partition{|r| common_ad_urls.include? r[:url]}

    # now that there are no more ads (blocked requests) in adblock,
    # all is left is non-ads.  move the common requests.
    adblock_urls, vanilla_urls = [@adblock, @vanilla].map{|s| Set.new(s.requests.map{|r| r[:url]})}
    common_urls = adblock_urls & vanilla_urls
    [@adblock, @vanilla].each{|s| s.common, s.requests = s.requests.partition{|r| common_urls.include? r[:url]}}

    # XXX do -depend matching

    # XXX similar matching should take a whole body of requests to
    # compare to, and a (smaller) list of requests that should be
    # sorted.

    # Now we come to the fuzzy processing to match similar enough
    # requests.

    # requests similar to adblocks' remaining ads are soft_ads.  The
    # rest that does not match is unknown_ads for adblock, and
    # whatever for vanilla.
    ((@adblock.soft_ads, @adblock.unknown_ads), (@vanilla.soft_ads, @vanilla.requests)) = similar(ads, @vanilla.requests)

    # XXX do -depend matching

    # what remains are similar common and what we could not classify
    # for adblock.
    ((@adblock.soft_common, @adblock.unknown), (@vanilla.soft_common, @vanilla.unknown)) = similar(@adblock.requests, @vanilla.requests)
    @adblock.requests = []
    @vanilla.requests = []

    [@adblock, @vanilla].each do |s|
      if s.count != s.original_count
        raise RuntimeError, "lost requests on the way"
      end
    end
  end

  # Takes a list of requests, returns a scored list of matches
  def similar(al, bl, threshold=62)
    similarities = []

    al.each do |a|
      aurl = split_url(a[:url])

      bl.each do |b|
        burl = split_url(b[:url])

        # we score for similarity
        score = 0

        aurl.each_with_index do |(k, av), i|
          bv = burl[k]

          # weigh scores so that protocol has the highest weight,
          # followed by host, then port, then path, then query string.
          score += match_strings(av, bv) * 2**(aurl.length - i)
        end

        [:mimeType].each do |f|
          score += match_strings(a[f], b[f])
        end

        [:redirect, :failed, :status].each do |f|
          if a[f] == b[f]
            score += 1
          end
        end

        [:dataLength].each do |f|
          min = [a[f], b[f]].min
          max = [a[f], b[f]].max

          if max.nil? ^ min.nil?
            # nope
            next
          elsif max.nil? && min.nik?
            score += 1
          elsif max == 0
            score += 1
          else
            score += min.to_f / max
          end
        end
        
        similarities << {:score => score, :a => a, :b => b}
      end
    end

    similarities.sort_by!{|i| -i[:score]}

    # greedily consume pairs
    common_a = Set.new
    common_b = Set.new
    while s = similarities.shift
      break if s[:score] < threshold

      if common_a.include?(s[:a]) || common_b.include?(s[:b])
        # one of these elements of the pair has already been consumed,
        # so skip it here.
        next
      end

      common_a << s[:a]
      common_b << s[:b]
    end

    unmatched_a = (Set.new(al) - common_a).to_a
    unmatched_b = (Set.new(bl) - common_b).to_a

    [[common_a.to_a, unmatched_a], [common_b.to_a, unmatched_b]]
  end
end

if __FILE__ == $0
  names = ARGV.map{|a| a.match(/^(.*?)-(?:adblock|vanilla)\.log$/) && $1}.compact.uniq

  names.each do |n|
    begin
      vanilla = Domain.new(n + "-vanilla.log")
      adblock = Domain.new(n + "-adblock.log")
    rescue Error::ENOENT
      puts "cannot find pair for #{n}"
    end

    adblock.process!
    vanilla.process!

    if adblock.requests.empty? || vanilla.requests.empty?
      puts "skipping #{n} because of empty requests"
      next
    end

    finder = AdFinder.new(adblock, vanilla)
    finder.classify

    require 'pp'
    puts n
    [finder.adblock, finder.vanilla].each do |l|
      pp l.stats
    end
  end
end
