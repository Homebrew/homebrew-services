Homebrew Services
=================

[![Build Status](https://travis-ci.org/Homebrew/homebrew-services.svg?branch=master)](https://travis-ci.org/Homebrew/homebrew-services)

Integrates homebrew formulae with MacOS X' `launchctl` manager.

By default plists are installed to `~/Library/LaunchAgents/` and run as the
current user upon login.  When `brew services` is run as the root user plists
are installed to `/Library/LaunchDaemons/`, and run as the root user on boot.

## Installation ##

```
brew tap homebrew/services
```

## Examples ##

### Install and start service mysql at login ###

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


### Install and start dnsmasq service at boot ###

```
$ brew install dnsmasq
$ sudo brew services start dnsmasq
```

### Start/stop/restart all available services ###

```
$ brew start|stop|restart --all
```
