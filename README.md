# Homebrew Services

Manage background services with macOS' `launchctl` daemon manager.

## Requirements

[Homebrew](https://github.com/Homebrew/brew) is used for installing the services.

This does not (and cannot) work with Homebrew on Linux (so don't file Linux issues, please).

## Install

`brew services` is automatically installed when first run.

## Usage

See [the `brew services` section of the `brew man` output](https://docs.brew.sh/Manpage#services-subcommand) or `brew services --help`.
To specify a plist file use `brew services <command> <formula> --file=<file>`.


## Tests

Tests can be run with `bundle install && bundle exec rspec`.

## Copyright

Copyright (c) Homebrew maintainers. See [LICENSE.txt](https://github.com/Homebrew/homebrew-services/blob/HEAD/LICENSE.txt) for details.
