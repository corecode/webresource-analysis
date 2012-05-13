CREATE TABLE initiator (
       domainId	       INTEGER,
       requestId       TEXT,
       timestamp       REAL,
       url	       TEXT,
       initiator       INTEGER,
       fromCache       INTEGER);

CREATE TABLE request (
       domainId		INTEGER,
       requestId	TEXT,
       timestamp	REAL,
       host		TEXT,
       connectionId	INTEGER,
       connectionReused INTEGER,
       mimeType		TEXT,
       status		INTEGER,
       didRedirect	INTEGER);

CREATE TABLE transfer (
       domainId		INTEGER,
       requestId	TEXT,
       timestamp	REAL,
       dataLength	INTEGER,
       encodedDataLength INTEGER);

