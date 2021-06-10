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
      flag "--file=", description: "Use the plist file from this location to start or run the service."
      switch "--all", description: "Run <subcommand> on all services."
    end
  end

  def services
    args = services_args.parse

    raise UsageError, "`brew services` is supported only on macOS!" unless OS.mac?

    # pbpaste's exit status is a proxy for detecting the use of reattach-to-user-namespace
    raise UsageError, "`brew services` cannot run under tmux!" if ENV["TMUX"] && !quiet_system("/usr/bin/pbpaste")

    # Keep this after the .parse to keep --help fast.
    require_relative "../lib/services_cli"

    # Parse arguments.
    subcommand, formula, custom_plist, = args.named

    if custom_plist.present?
      odeprecated "with file as last argument", "`--file=` to specify a plist file"
    else
      custom_plist = args.file
    end

    if ["list", "cleanup"].include?(subcommand)
      raise UsageError, "The `#{subcommand}` subcommand does not accept a formula argument!" if formula
      raise UsageError, "The `#{subcommand}` subcommand does not accept the --all argument!" if args.all?
    end

    target = if args.all?
      Homebrew::ServicesCli.available_services
    elsif formula
      Service.new(Formulary.factory(formula))
    end

    # Dispatch commands and aliases.
    case subcommand.presence
    when nil, "list", "ls"
      Homebrew::ServicesCli.list
    when "cleanup", "clean", "cl", "rm"
      Homebrew::ServicesCli.cleanup
    when "restart", "relaunch", "reload", "r"
      Homebrew::ServicesCli.check(target) &&
        Homebrew::ServicesCli.restart(target, custom_plist, verbose: args.verbose?)
    when "run"
      Homebrew::ServicesCli.check(target) &&
        Homebrew::ServicesCli.run(target)
    when "start", "launch", "load", "s", "l"
      Homebrew::ServicesCli.check(target) &&
        Homebrew::ServicesCli.start(target, custom_plist, verbose: args.verbose?)
    when "stop", "unload", "terminate", "term", "t", "u"
      Homebrew::ServicesCli.check(target) &&
        Homebrew::ServicesCli.stop(target)
    else
      raise UsageError, "unknown subcommand: `#{subcommand}`"
    end
  end
end
