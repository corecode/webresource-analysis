$: << File.expand_path("..", __FILE__)

require 'network'

class CsvPrint
  Fields = %w{domainId requestId host initiator cached dataLength encodedDataLength mimeType status redirect}.map(&:to_sym)

  def initialize(outf=$stdout, options={})
    @opts = options.merge({:delim => ","})
    @escapere = Regexp.new((%w{" ' \\ } + [@opts[:delim]]).join)
    @outf = outf
    @outf.puts "# %s" % Fields.join(@opts[:delim])
  end

  def finish
  end

  def add_domain(id, l)
    if !Array === l
      l = [l]
    end
    l.each do |data|
      data[:domainId] = id
      fs = Fields.map do |f|
        it = data[f].to_s
        if it.match(@escapere)
          it = '"%s"' % it.gsub(/[\\"]/, "\\$1")
        end
        it
      end

      @outf.puts fs.join(@opts[:delim])
    end
  end
end

if $0 == __FILE__
  id = 0
  p = CsvPrint.new
  ARGV.each do |f|
    id += 1
    d = Domain.new(f)
    p.add_domain(id, d.process)
  end
  p.finish
end
