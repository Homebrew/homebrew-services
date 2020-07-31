# frozen_string_literal: true

require "cli/parser"

module Homebrew
  module_function

  def services_args
    Homebrew::CLI::Parser.new do
      usage_banner <<~EOS
        `services` [<subcommand>]

        Manage background services with macOS' `launchctl`(1) daemon manager.

        If `sudo` is passed, operate on `/Library/LaunchDaemons` (started at boot).
        Otherwise, operate on `~/Library/LaunchAgents` (started at login).

        [`sudo`] `brew services` [`list`]:
        List all managed services for the current user (or root).

        [`sudo`] `brew services run` (<formula>|`--all`):
        Run the service <formula> without registering to launch at login (or boot).

        [`sudo`] `brew services start` (<formula>|`--all`):
        Start the service <formula> immediately and register it to launch at login (or boot).

        [`sudo`] `brew services stop` (<formula>|`--all`):
        Stop the service <formula> immediately and unregister it from launching at login (or boot).

        [`sudo`] `brew services restart` (<formula>|`--all`):
        Stop (if necessary) and start the service <formula> immediately and register it to launch at login (or boot).

        [`sudo`] `brew services cleanup`:
        Remove all unused services.
      EOS
      switch "--all", description: "Run <subcommand> on all services."
    end
  end

  def services
    args = services_args.parse

    raise UsageError, "`brew services` is supported only on macOS!" unless OS.mac?

    # Keep this after the .parse to keep --help fast.
    require_relative "../lib/services_cli"

    Homebrew::ServicesCli.run!(args)
  end
end
