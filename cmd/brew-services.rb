# frozen_string_literal: true

#:  * `services` <subcommand>:
#:
#:  Manage background services with macOS' `launchctl`(1) daemon manager
#:
#:       --all                           run <subcommand> on all services.
#:
#:  [`sudo`] `brew services list`
#:
#:  List all running services for the current user (or root).
#:
#:  [`sudo`] `brew services run` (<formula>|`--all`)
#:
#:  Run the service <formula> without registering to launch at login (or boot).
#:
#:  [`sudo`] `brew services start` (<formula>|`--all`)
#:
#:  Start the service <formula> immediately and register it to launch at login (or boot).
#:
#:  [`sudo`] `brew services stop` (<formula>|`--all`)
#:
#:  Stop the service <formula> immediately and unregister it from launching at login (or boot).
#:
#:  [`sudo`] `brew services restart` (<formula>|`--all`)
#:
#:  Stop (if necessary) and start the service <formula> immediately and register it to launch at login (or boot).
#:
#:  [`sudo`] `brew services cleanup`
#:
#:  Remove all unused services.
#:
#:  If `sudo` is passed, operate on `/Library/LaunchDaemons` (started at boot).
#:  Otherwise, operate on `~/Library/LaunchAgents` (started at login).

unless defined? HOMEBREW_LIBRARY_PATH
  abort "Runtime error: Homebrew is required. Please start via `#{bin} ...`"
end

odie "brew services is supported only on macOS" unless OS.mac?

require_relative "../lib/services_cli"

# Start the CLI dispatch stuff.
#
ServicesCli.run!
