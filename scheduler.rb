$: << File.expand_path('..', $0)

require 'csvprint'

class Scheduler
  def initialize(concurrency=1, printer=CsvPrint.new)
    @concurrency = concurrency
    @p = printer
  end

  def run(dir=".")
    STDOUT.sync = true
    files = Dir.glob(File.join(dir, '*.log'))
    kids = []
    tm = Mutex.new
    files.each_slice(files.size / @concurrency).each_with_index do |l, p_id|
      kids << Thread.start(p_id) do |d_id|
        l.each do |d|
          d = Domain.new(d)
          data = d.process

          tm.synchronize do
            @p.add_domain(d_id, data)
          end
          d_id += @concurrency
        end
      end
    end
    kids.each do |k|
      k.join
    end
    @p.finish
  end
end

if $0 == __FILE__
  s = Scheduler.new((ARGV.shift || 1).to_i)
  s.run(*ARGV)
end
