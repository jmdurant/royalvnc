#!/usr/bin/env bash

set -e

export HOMEBREW_NO_REQUIRE_TAP_TRUST=1

echo "Installing Skip using homebrew"
brew install skiptools/skip/skip

echo "Installing Skip Android SDK"
skip android sdk install 6.2.3

echo "All Done"