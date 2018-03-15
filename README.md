# Homebrew Services

Integrates Homebrew formulae with macOS' `launchctl` manager.

[![Build Status](https://travis-ci.org/Homebrew/homebrew-services.svg?branch=master)](https://travis-ci.org/Homebrew/homebrew-services)

## Requirements

[Homebrew](https://github.com/Homebrew/brew) is used for installing the services.

This does not work with Linuxbrew (so don't file Linux issues, please).

## Install

`brew services` is automatically installed when run.

## Usage

### Start

Start the MySQL service at login with:

```
brew services start mysql
```

Start the Dnsmasq service at boot with:

```
$ sudo brew services start dnsmasq
```

Start all available services with:
```
$ brew services start --all
```

### Run

Run the MySQL service but don't start it at login (nor boot) with:

```
$ brew services run mysql
```

### Stop

Stop the MySQL service with:

```
$ brew services stop mysql
```

### Restart

Restart the MySQL service with:

```
$ brew services restart mysql
```

### List

List all services managed by `brew services` with:

```
$ brew services list
```

### Cleanup

Remove all unused services with:

```
$ brew services list
```

## Copyright

Copyright (c) Homebrew maintainers. See [LICENSE.txt](https://github.com/Homebrew/homebrew-services/blob/master/LICENSE.txt) for details.
