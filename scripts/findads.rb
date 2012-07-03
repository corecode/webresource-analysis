$: << File.expand_path('..', $0)

require 'network'
require 'set'

class AdFinder
  def initialize(adblock_reqs, vanilla_reqs)
    @adblock_reqs, @vanilla_reqs = adblock_reqs, vanilla_reqs
    @common = nil
    @ads = nil
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
    similarities = []

    adblock_set, vanilla_set = [@adblock_reqs, @vanilla_reqs].map do |rs|
      reverse_map = Hash.new{|h, k| h[k] = []}

      rs.each do |r|
        next if r[:status] == -1 # reject adblock connection blocks

        reduced = {}
        [:url, :mimeType, :status, :redirect, :failed].map do |f|
          reduced[f] = r[f]
        end
        reverse_map[reduced] << r
      end
      reverse_map
    end

    @common = []
    (Set.new(adblock_set.keys) & Set.new(vanilla_set.keys)).each do |e|
      @common += vanilla_set[e]
      vanilla_set.delete(e)
      adblock_set.delete(e)
    end

    # Now we need to match all those that didn't have equivalents
    adblock_un = adblock_set.inject([]){|a, e| a += e[1]}
    vanilla_un = vanilla_set.inject([]){|a, e| a += e[1]}

    adblock_un.each do |r|
      rurl = split_url(r[:url])

      vanilla_un.each do |v|
        vurl = split_url(v[:url])

        # we score for similarity
        score = 0

        rurl.each_with_index do |(k, rv), i|
          vv = vurl[k]

          # weigh scores so that protocol has the highest weight,
          # followed by host, then port, then path, then query string.
          score += match_strings(rv, vv) * 2**(rurl.length - i)
        end

        [:mimeType].each do |f|
          score += match_strings(r[f], v[f])
        end

        [:redirect, :failed, :status].each do |f|
          if r[f] == v[f]
            score += 1
          end
        end

        [:dataLength].each do |f|
          min = [r[f], v[f]].min
          max = [r[f], v[f]].max

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

        if score.nan? || score > 100
          require 'pp'
          pp r, v, score
          
        end
        
        similarities << {:score => score, :adblock => r, :vanilla => v}
      end
    end

    similarities.sort_by!{|i| -i[:score]}

    # greedily consume pairs
    while s = similarities.shift
      require 'pp'
      pp s if s[:score] <= 62.0
      similarities.delete_if{|i| i[:adblock] == s[:adblock] || i[:vanilla] == s[:vanilla]}
    end
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

    finder = AdFinder.new(adblock.process, vanilla.process)
    finder.classify
  end
end
