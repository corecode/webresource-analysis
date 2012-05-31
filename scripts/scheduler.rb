$: << File.expand_path('..', $0)

require 'csvprint'
require 'sqlprint'
require 'xmlprint'

class Scheduler
  def initialize(concurrency=1, printers)
    @concurrency = concurrency
    @p = printers
  end

  def run(dir=".")
    STDOUT.sync = true
    files = Dir.glob(File.join(dir, '*.log'))
    kids = []
    tm = Mutex.new
    files.each_slice(files.size / @concurrency).each_with_index do |l, p_id|
      kids << Thread.start(p_id) do |d_id|
        l.each do |d|
          d = Domain.new(d, d_id)
          data = d.process

          tm.synchronize do
            @p.each do |p|
              p.add_domain(data)
            end
          end
          d_id += @concurrency
        end
      end
    end
    kids.each do |k|
      k.join
    end
    @p.each do |p|
      p.finish
    end
  end
end

if $0 == __FILE__
  require 'getoptlong'

  opts = GetoptLong.new(
                        [ '--concurrency', '-c', GetoptLong::REQUIRED_ARGUMENT ],
                        [ '--output', '-o', GetoptLong::REQUIRED_ARGUMENT ],
                        )

  concurrency = 1
  printers = []
  opts.each do |opt, arg|
    case opt
    when '--concurrency'
      concurrency = arg.to_i
    when '--output'
      m = arg.match(/(?:([^:]+):)?((?:.*?)(?:[.]([^.]+))?)$/)
      if !m || (!m[1] && !m[3])
        $stdout.puts "output requires type specification, e.g. `sql:foo' or `foo.sql'"
        exit 1
      end
      type = m[1] || m[3]
      begin
        p_class = Kernel.const_get("%sPrint" % type.capitalize)
      rescue NameError
        $stdout.puts "invalid output printer `#{type}'"
        exit 1
      end
      case m[2]
      when "", "-"
        outf = $stdout
      else
        outf = File.open(m[2], 'w')
      end
      printers << p_class.new(outf)
    end
  end

  if printers.empty?
    printers << CsvPrint.new
  end

  s = Scheduler.new(concurrency, printers)
  s.run(*ARGV)
end
