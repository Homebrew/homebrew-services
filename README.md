Homebrew Services
=================

[![Build Status](https://travis-ci.org/Homebrew/homebrew-services.svg?branch=master)](https://travis-ci.org/Homebrew/homebrew-services)

Integrates Homebrew formulae with macOS's `launchctl` manager.

By default, plists are installed to `~/Library/LaunchAgents/` and run as the
current user upon login.  When `brew services` is run as the root user, plists
are installed to `/Library/LaunchDaemons/`, and run as the root user on boot.

## Installation ##

```
brew tap homebrew/services
```

## Examples ##

### Start service mysql ###

```
$ brew install mysql
$ brew services start mysql
```

Stop service mysql:

```
$ brew services stop mysql
```

Restart service mysql:

```
$ brew services restart mysql
```

Install and start service mysql at login:

```
$ brew services install mysql
```

### Install and start dnsmasq service at boot ###

```
$ brew install dnsmasq
$ sudo brew services install dnsmasq
```

### List all services managed by `brew services` ###

```
$ brew services list
```

### Start/stop/restart all available services ###

```
$ brew services start|stop|restart --all
```
