$: << File.expand_path('..', $0)

require 'thread'
require 'timeout'

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

    kid_stat = {}
    m = Mutex.new

    kids = {}
    @concurrency.times do |p_id|
      kids[p_id] = Thread.start(p_id) do |d_id|
        thread_id = d_id

        begin
          while true
            d_id += @concurrency
            n = workqueue.pop(true)

            m.synchronize do
              $stderr.puts "% 3d: % 5d/%d %s" % [thread_id, workqueue.length, total_count, n]
              kid_stat[thread_id] = n
            end

            r = nil
            begin
              Timeout.timeout(60) do
                r = process_name(n, d_id)
              end
            rescue Timeout::Error
              $stderr.puts "% 3d: timeout processing %s" % [thread_id, n]
              next
            end

            @tm.synchronize do
              r.each do |mode, dom|
                @p[mode].each do |p|
                  p.add_domain(dom)
                end
              end
            end
            m.synchronize do
              kid_stat.delete(thread_id)
            end
          end
        rescue ThreadError
          # queue empty, exit.
        end
      end
    end
    # wait until we see stragglers
    while !workqueue.empty?
      sleep 1
    end

    while !kids.empty?
      sleep 5
      kids_done = []
      kids.each do |thread_id, td|
        m.synchronize do
          if !td.alive?
            td.join
            kids_done << thread_id
          else
            n = kid_stat[thread_id]

            if !n
              $stderr.puts "thread #{thread_id} alive, but not working?"
            else
              $stderr.puts "waiting for thread #{thread_id} processing #{n}"
            end
          end
        end
      end
      kids_done.each do |thread_id|
        kids.delete thread_id
      end
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
    finder.adblock.assign_adstate!
    finder.vanilla.assign_adstate!

    {"adblock" => finder.adblock.all, "vanilla" => finder.vanilla.all}
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
