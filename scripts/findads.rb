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

    2.0 * score / union
  end

  def classify
    adblock_urls = Set.new(@adblock_reqs.map{|r| r[:url]})
    vanilla_urls = Set.new(@vanilla_reqs.map{|r| r[:url]})

    common_urls = adblock_urls & vanilla_urls

    adblock_un = @adblock_reqs.select{|r| not common_urls.include? r[:url]}
    vanilla_un = @vanilla_reqs.select{|r| not common_urls.include? r[:url]}

    @common = @adblock_reqs.select{|r| common_urls.include? r[:url]}

    # The easy part is over.  Now try matching vanilla requests to all
    # unmatched adblock requests.

    puts "#{@common.length} common requests.  #{vanilla_un.length} unmatched vanilla, #{adblock_un.length} unmatched adblock."

    urlesc = /\s\[\][|]/
    
    adblock_un.each do |r|
      if not r[:url]
        require 'pp'
        pp r
        
      end
      rurl = split_url(r[:url])

      puts "trying to match #{r[:url]}"

      similarities = []
      vanilla_un.each do |v|
        vurl = split_url(v[:url])

        # we score for similarity
        score = 0
        rurl.each do |k, rv|
          vv = vurl[k]

          if !rv ^ !vv
            # one has it, the other doesn't.  No score!
            next
          elsif !rv
            score += 1
            next
          end

          # both have a string.  score their similarity
          partscore = match_strings(rv, vv)
          # puts "%0.3f\t%s vs %s" % [partscore, rv, vv]
          score += partscore
        end

        similarities << [score, v]
      end

      similarities.sort_by!{|i| -i[0]}

      # The maximum score is 5.  Let's say that anything below 4
      # (i.e. 1 completely different) is unaccetable.
      similarities.reject!{|i| i[0] < 4}
      similarities.each do |score, v|
        puts "\t%0.3f\t%s" % [score, v[:url]]
      end
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
