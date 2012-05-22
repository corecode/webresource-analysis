$: << File.expand_path("..", __FILE__)

require 'network'

class CsvPrint
  Fields = Domain::Fields.keys
  
  def initialize(outf=$stdout, options={})
    @opts = options.merge({:delim => ","})
    @outf = outf
    print_header
  end

  def print_header
    os = Fields.join(@opts[:delim])
    if @opts[:delim] == ?\t
      os = "# " + os
    end
    @outf.puts os
  end

  def finish
  end

  def add_domain(l, id=nil)
    if !Array === l
      l = [l]
    end
    l.each do |data|
      fs = Fields.map do |f|
        it = data[f].to_s
        # always quote non-numerics
        unless Numeric === data[f]
          it = '"%s"' % it.gsub(/[\\"]/, "\\$1")
        end
        it
      end

      os = fs.join(@opts[:delim])
      @outf.puts os
    end
  end
end

if $0 == __FILE__
  id = 0
  p = CsvPrint.new
  ARGV.each do |f|
    id += 1
    d = Domain.new(f, id)
    p.add_domain(d.process)
  end
  p.finish
end
