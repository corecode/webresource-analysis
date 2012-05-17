$: << File.realpath("..", __FILE__)

require 'network'

class SqlPrint
  Schema = <<-ends
CREATE TABLE request (
       domainId        INTEGER,
       requestId       TEXT,
       timestamp       REAL,
       url             TEXT,
       initiator       INTEGER,
       fromCache       INTEGER);

CREATE TABLE resource (
       domainId         INTEGER,
       requestId        TEXT,
       timestamp        REAL,
       host             TEXT,
       connectionId     INTEGER,
       connectionReused INTEGER,
       mimeType         TEXT,
       status           INTEGER,
       didRedirect      INTEGER);

CREATE TABLE transfer (
       domainId         INTEGER,
       requestId        TEXT,
       timestamp        REAL,
       dataLength       INTEGER,
       encodedDataLength INTEGER);
ends
  
  def initialize(outf=$stdout)
    @outf = outf
    @outf.puts Schema
    @outf.puts "BEGIN TRANSACTION;"
  end

  def finish
    @outf.puts "COMMIT TRANSACTION;"
  end

  def resource(data)
    insert('resource', data)
  end

  def request(data)
    insert('request', data)
  end

  def transfer(data)
    insert('transfer', data)
  end

  def insert(table, data)
    @outf.puts 'INSERT INTO %s (%s) VALUES (%s);' %
      [
       table,
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
    d = Domain.new(f, id, p)
    d.process
  end
  p.finish
end
