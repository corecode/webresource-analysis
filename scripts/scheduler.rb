$: << File.expand_path('..', $0)

require 'thread'

require 'findads'
require 'csvprint'
require 'sqlprint'
require 'xmlprint'

class Scheduler
  def initialize(printers, opts={})
    @concurrency = opts[:concurrency] || 1
    @verbose = opts[:verbose] || false
    @p = printers
    @tm = Mutex.new
  end

  def run(dir=".")
    STDOUT.sync = true
    files = Dir.glob(File.join(dir, '*.log'))

    names = files.map{|a| a.match(/^(.*?)-(?:adblock|vanilla)\.log$/) && $1}.compact.uniq

    workqueue = Queue.new
    names.each do |n|
      workqueue << n
    end

    total_count = names.length

    kids = []
    @concurrency.times do |p_id|
      kids << Thread.start(p_id) do |d_id|
        begin
          while true
            n = workqueue.pop(true)

            $stderr.puts "#{n} (#{workqueue.length}/#{total_count})" if @verbose

            process_name(n, d_id)
            d_id += @concurrency
          end
        rescue ThreadError
          # queue empty, exit.
        end
      end
    end
    kids.each do |k|
      k.join
    end
    @p.values.flatten.each do |p|
      p.finish
    end
  end

  def process_name(n, id)
    begin
      vanilla = Domain.new(n + "-vanilla.log", id)
      adblock = Domain.new(n + "-adblock.log", id)
    rescue Error::ENOENT
      $stderr.puts "cannot find pair for #{n}"
    end

    vanilla.process!
    adblock.process!

    if adblock.requests.empty? || vanilla.requests.empty?
      $stderr.puts "skipping #{n} because of empty requests"
      return
    end

    finder = AdFinder.new(adblock, vanilla)
    finder.classify

    [[finder.adblock, @p["adblock"]], [finder.vanilla, @p["vanilla"]]].each do |l, printers|
      next unless printers && !printers.empty?

      l.assign_adstate!
      @tm.synchronize do
        printers.each do |p|
          p.add_domain(l.all)
        end
      end
    end
  end
end

if $0 == __FILE__
  require 'getoptlong'

  opts = GetoptLong.new(
                        [ '--concurrency', '-c', GetoptLong::REQUIRED_ARGUMENT ],
                        [ '--output', '-o', GetoptLong::REQUIRED_ARGUMENT ],
                        [ '--vanilla-output', GetoptLong::REQUIRED_ARGUMENT ],
                        [ '--adblock-output', GetoptLong::REQUIRED_ARGUMENT ],
                        [ '--verbose', '-v', GetoptLong::NO_ARGUMENT ],
                        )

  sched_opts = {}

  printers = Hash.new{|h,k| h[k] = []}
  opts.each do |opt, arg|
    case opt
    when '--concurrency'
      sched_opts[:concurrency] = arg.to_i
    when /--(.*)output/
      if !$1.empty?
        output_mode = [$1]
      else
        output_mode = ['vanilla', 'adblock']
      end

      m = arg.match(/(?:([^:]+):)?((.*?)([.]([^.]+))?)$/)

      if !m || (!m[1] && !m[4])
        $stderr.puts "output requires type specification, e.g. `sql:foo' or `foo.sql'"
        exit 1
      end
      type = m[1] || m[5]
      begin
        p_class = Kernel.const_get("%sPrint" % type.capitalize)
      rescue NameError
        $stderr.puts "invalid output printer `#{type}'"
        exit 1
      end

      fname = m[2]
      case fname
      when "", "-"
        if output_mode.length != 1
          $stderr.puts "can only do either adblock or vanilla when writing to stdout"
          exit 1
        end
        printers[output_mode] << p_class.new
      else
        output_mode.each do |mode|
          fname = "%s-%s%s" % [m[3], mode, m[4]]
          outf = File.open(fname, 'w')
          printers[mode] << p_class.new(outf)
        end
      end
    when '--verbose'
      sched_opts[:verbose] = true
    end
  end

  if printers.empty?
    $stderr.puts "need output specification"
    exit 1
  end

  s = Scheduler.new(printers, sched_opts)
  s.run(*ARGV)
end
