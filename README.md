# Homebrew Services

Integrates Homebrew formulae with macOS' `launchctl` manager.

[![Azure Pipelines](https://img.shields.io/vso/build/Homebrew/56a87eb4-3180-495a-9117-5ed6c79da737/4.svg)](https://dev.azure.com/Homebrew/Homebrew/_build/latest?definitionId=4)

## Requirements

[Homebrew](https://github.com/Homebrew/brew) is used for installing the services.

This does not work with Linuxbrew (so don't file Linux issues, please).

## Install

`brew services` is automatically installed when run.

## Usage

### Start

Start the MySQL service at login with:

```bash
brew services start mysql
```

Start the Dnsmasq service at boot with:

```bash
sudo brew services start dnsmasq
```

Start all available services with:

```bash
brew services start --all
```

### Run

Run the MySQL service but don't start it at login (nor boot) with:

```bash
brew services run mysql
```

### Stop

Stop the MySQL service with:

```bash
brew services stop mysql
```

### Restart

Restart the MySQL service with:

```bash
brew services restart mysql
```

### List

List all services managed by `brew services` with:

```bash
brew services list
```

### Cleanup

Remove all unused services with:

```bash
brew services cleanup
```

## Copyright

Copyright (c) Homebrew maintainers. See [LICENSE.txt](https://github.com/Homebrew/homebrew-services/blob/master/LICENSE.txt) for details.
