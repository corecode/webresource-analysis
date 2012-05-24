$: << File.expand_path("..", __FILE__)

require 'network'

class SqlPrint
  Fields = Domain::Fields.keys

  def initialize(outf=$stdout)
    @outf = outf
    print_header
  end

  def print_header
    @outf.puts "CREATE TABLE resource (\n\t%s\n);" % Domain::Fields.map{|k, v|
      "%s\t%s" % [k, case v
                    when Numeric, true, false
                      "INTEGER"
                    else
                      "TEXT"
                    end]
    }.join(",\n\t")
    @outf.puts "BEGIN TRANSACTION;"
  end

  def finish
    @outf.puts "COMMIT TRANSACTION;"
  end

  def add_domain(l, id=nil)
    if !Array === l
      l = [l]
    end
    l.each do |data|
      @outf.puts 'INSERT INTO resource VALUES (%s);' %
        [
         Fields.map do |f|
           d = data[f]
           case d
           when Numeric
             d.to_s
           when nil, ""
             'NULL'
           when true, false
             d ? "1" : "0"
           else
             '"%s"' % d.to_s.gsub(/[\\"]/, "\\$1")
           end
         end.join(', ')
        ]
    end
  end
end

if $0 == __FILE__
  id = 0
  p = SqlPrint.new
  ARGV.each do |f|
    id += 1
    d = Domain.new(f, id)
    p.add_domain(d.process)
  end
  p.finish
end
