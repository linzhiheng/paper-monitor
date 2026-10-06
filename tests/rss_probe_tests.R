source("R/config_layer.R")
source("R/llm_layer.R")
source("R/rss_layer.R")

expect_true <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)

generic_xml <- xml2::read_xml('
<rss><channel>
  <title>Example Journal</title>
  <item><title>Paper One</title><description>Abstract one</description><link>https://example.org/one</link><pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate></item>
  <item><title>Paper Two</title><description>Abstract two</description><link>https://example.org/two</link><pubDate>Tue, 02 Jan 2024 00:00:00 GMT</pubDate></item>
</channel></rss>')

generic_probe <- probe_rss_document(generic_xml)
expect_true(identical(generic_probe$suggested_journal, "Example Journal"), "The channel title should suggest a journal name.")
expect_true(identical(generic_probe$recommended_parser, "Generic"), "Generic should win a quality tie because it is the safest fallback.")
expect_true(generic_probe$attempts$Generic$status$success, "The recommended generic parser should parse the fixture.")
expect_true(nrow(generic_probe$attempts$Generic$data) == 2L, "The probe should retain a preview of parsed articles.")
expect_true(all(generic_probe$attempts$Generic$data$journal == "Example Journal"), "The suggested journal should be used in fallback previews.")

egu_xml <- xml2::read_xml('
<rss><channel>
  <title>Example EGU Journal</title>
  <item><title>EGU Paper</title><description><![CDATA[Header<br/>Alice Example<br/>Citation<br/>Detailed abstract]]></description><link>https://example.org/egu</link><guid>https://doi.org/10.1234/example</guid><pubDate>Wed, 03 Jan 2024 00:00:00 GMT</pubDate></item>
</channel></rss>')

egu_probe <- probe_rss_document(egu_xml)
expect_true(identical(egu_probe$recommended_parser, "EGU"), "A parser that extracts additional author and DOI data should outrank Generic.")
expect_true(egu_probe$attempts$EGU$quality > egu_probe$attempts$Generic$quality, "Parser quality should reward richer parsed fields.")

atom_xml <- xml2::read_xml('<feed xmlns="http://www.w3.org/2005/Atom"><title>Atom Journal</title></feed>')
expect_true(identical(rss_feed_title(atom_xml), "Atom Journal"), "Atom feed titles should also be detected.")
untitled_xml <- xml2::read_xml('<rss><channel><item><title>Untitled item</title></item></channel></rss>')
expect_true(identical(probe_rss_document(untitled_xml)$suggested_journal, "Untitled RSS feed"), "Feeds without a title should have an editable fallback name.")

cat("rss_probe_tests: PASS\n")
