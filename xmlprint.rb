$: << File.expand_path("..", __FILE__)

require 'network'

class XmlPrint
  Fields = Hash[*Domain::Fields.map{|f, t| [f, Numeric === t ? "int" : "string"]}.flatten]

  def initialize(outf=$stdout)
    @outf = outf
    @data = []
  end
  
  def add_domain(l, id=nil)
    @data.concat l
  end

  def finish
    @outf.puts <<eos
<?xml version="1.0"?>
<!DOCTYPE ggobidata SYSTEM "ggobi.dtd">

<ggobidata>

<data>
eos
    @outf.puts "<variables count='#{Fields.count + 1}'>"
    @outf.puts "  <countervariable name='id' />"
    Fields.each do |f, t|
      case t
      when "string"
        @outf.puts "  <categoricalvariable name='#{f}' levels='auto' />"
      when "int"
        @outf.puts "  <integervariable name='#{f}' />"
      else
        raise RuntimeError, "unknown field type"
      end
    end
    @outf.puts "</variables>"
    @outf.puts "<records count='#{@data.count}'>"
    @data.each do |data|
      s = Fields.map do |f, t|
        d = data[f].to_s
        t = 'na' if d.empty?
        "<#{t}>#{d}</#{t}>"
      end
      @outf.puts "  <record>%s</record>" % s.join
    end
    @outf.puts "</records>"
    @outf.puts "</data>"
    @outf.puts "</ggobidata>"
  end
end

if $0 == __FILE__
  id = 0
  p = XmlPrint.new
  ARGV.each do |f|
    id += 1
    d = Domain.new(f, id)
    p.add_domain(d.process)
  end
  p.finish
end
