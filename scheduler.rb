$: << File.expand_path('..', $0)

require 'network'

class Scheduler
  def initialize(concurrency=1)
    @concurrency = concurrency
  end

  def run(dir=".")
    files = Dir.glob(File.join(dir, '*.log'))
    kids = []
    files.each_slice(files.size / @concurrency).each_with_index do |l, p_id|
      kids << fork do
        d_id = p_id
        l.each do |d|
          d = Domain.new(d, d_id)
          d.process
          d_id += @concurrency
        end
      end
    end
    kids.each do |k|
      Process.wait(k)
    end
  end
end

if $0 == __FILE__
  s = Scheduler.new((ARGV.shift || 1).to_i)
  s.run(*ARGV)
end
