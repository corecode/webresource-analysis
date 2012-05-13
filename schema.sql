CREATE TABLE initiator (
       domainId	       INTEGER,
       requestId       TEXT,
       timestamp       REAL,
       url	       TEXT,
       initiator       INTEGER,
       fromCache       INTEGER);

CREATE INDEX initiator_req ON initiator (domainId, requestId);

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

CREATE INDEX request_req ON request (domainId, requestId);

CREATE TABLE transfer (
       domainId		INTEGER,
       requestId	TEXT,
       timestamp	REAL,
       dataLength	INTEGER,
       encodedDataLength INTEGER);

CREATE INDEX transfer_req ON transfer (domainId, requestId);
