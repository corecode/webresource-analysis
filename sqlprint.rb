$: << File.realpath("..", __FILE__)

require 'network'

class SqlPrint
  Schema = <<-ends
CREATE TABLE resource (
       domainId        INTEGER,
       requestId       TEXT,
       url             TEXT,
       host            TEXT,
       initiator       INTEGER,
       cached          INTEGER,
       dataLength      INTEGER,
       encodedDataLength INTEGER,
       mimeType        TEXT,
       status          INTEGER,
       redirect        INTEGER
);
ends
  
  def initialize(outf=$stdout)
    @outf = outf
    @outf.puts Schema
    @outf.puts "BEGIN TRANSACTION;"
  end

  def finish
    @outf.puts "COMMIT TRANSACTION;"
  end

  def <<(data)
    if Array === data
      data.each do |d|
        self.<< d
      end
      return
    end
    @outf.puts 'INSERT INTO resource (%s) VALUES (%s);' %
      [
       data.keys.join(', '),
       data.values.map { |d|
         case d
         when Numeric
           d.to_s
         when nil
           'NULL'
         else
           "\"#{d}\""
         end
       }.join(', ')
      ]
  end
end

if $0 == __FILE__
  id = 0
  p = SqlPrint.new
  ARGV.each do |f|
    id += 1
    d = Domain.new(f, id)
    p << d.process
  end
  p.finish
end
