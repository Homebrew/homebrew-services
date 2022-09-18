# Homebrew Services

Manage background services using the daemon manager `launchctl` on macOS or `systemctl` on Linux.

## Requirements

[Homebrew](https://github.com/Homebrew/brew) is used for installing the services.

## Install

`brew services` is automatically installed when first run.

## Usage

See [the `brew services` section of the `man brew` output](https://docs.brew.sh/Manpage#services-subcommand) or `brew services --help`.  
To specify a service file use `brew services <command> <formula> --file=<file>`.


## Tests

Tests can be run with `bundle install && bundle exec rspec`.

## Copyright

Copyright (c) Homebrew maintainers. See [LICENSE.txt](https://github.com/Homebrew/homebrew-services/blob/HEAD/LICENSE.txt) for details.
