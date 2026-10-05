# Release vulnerability policy

The release build blocks all HIGH and CRITICAL vulnerabilities with an
upstream fixed version. Vulnerabilities reported without a fixed version are
reported in the bundled Trivy JSON but are temporarily excluded from the
blocking result through 2026-09-27. This exception exists solely for the
Ubuntu kernel-development package inherited from the pinned R base image and
must be reviewed before any later release.
