#!/bin/sh
set -eu

for test_file in tests/*_tests.R; do
  # Local-only prototype validation; run manually when developing the prototype.
  if [ "$test_file" = "tests/must_read_interview_prototype_tests.R" ]; then
    continue
  fi
  Rscript "$test_file"
done
