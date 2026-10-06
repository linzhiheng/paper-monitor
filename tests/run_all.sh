#!/bin/sh
set -eu

for test_file in tests/*_tests.R; do
  Rscript "$test_file"
done
