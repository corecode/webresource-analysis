require(ggplot2)
require(plyr)

sample_domains <- function(domains, ...) {
  ids <- unique(domains$domainId)
  sids <- sample(ids, ...)
  res <- subset(domains, domainId %in% sids)
  return (res)
}

add_mime_class <- function(domains) {
  domains$mimeClass <- laply(strsplit(as.vector(domains$mimeType), "/"),
                             .fun = function(x) {
                               if (length(x) > 0)
                                 x[[1]]
                               else ""
                             })
  return (domains)
}

