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

        [`sudo`] `brew services` [`list`] (`--json`):
        List information about all managed services for the current user (or root).

        [`sudo`] `brew services info` (<formula>|`--all`|`--json`):
        List all managed services for the current user (or root).

        [`sudo`] `brew services run` (<formula>|`--all`):
        Run the service <formula> without registering to launch at login (or boot).

        [`sudo`] `brew services start` (<formula>|`--all`):
        Start the service <formula> immediately and register it to launch at login (or boot).

        [`sudo`] `brew services stop` (<formula>|`--all`):
        Stop the service <formula> immediately and unregister it from launching at login (or boot).

        [`sudo`] `brew services kill` (<formula>|`--all`):
        Stop the service <formula> immediately but keep it registered to launch at login (or boot).

        [`sudo`] `brew services restart` (<formula>|`--all`):
        Stop (if necessary) and start the service <formula> immediately and register it to launch at login (or boot).

        [`sudo`] `brew services cleanup`:
        Remove all unused services.
      EOS
      flag "--file=", description: "Use the plist file from this location to `start` or `run` the service."
      switch "--all", description: "Run <subcommand> on all services."
      switch "--json", description: "Output as JSON."
    end
  end

  def services
    args = services_args.parse

    # pbpaste's exit status is a proxy for detecting the use of reattach-to-user-namespace
    if ENV["HOMEBREW_TMUX"] && (File.exist?("/usr/bin/pbpaste") && !quiet_system("/usr/bin/pbpaste"))
      raise UsageError,
            "`brew services` cannot run under tmux!"
    end

    # Keep this after the .parse to keep --help fast.
    require_relative "../lib/service"
    require "utils"

    if !Service::System.launchctl? && !Service::System.systemctl?
      raise UsageError,
            "`brew services` is supported only on macOS or Linux (with systemd)!"
    end

    # Parse arguments.
    subcommand, formula, custom_plist, = args.named

    if custom_plist.present?
      odeprecated "with file as last argument", "`--file=` to specify a plist file"
    else
      custom_plist = args.file
    end

    if [*Service::Commands::List::TRIGGERS, *Service::Commands::Cleanup::TRIGGERS].include?(subcommand)
      raise UsageError, "The `#{subcommand}` subcommand does not accept a formula argument!" if formula
      raise UsageError, "The `#{subcommand}` subcommand does not accept the --all argument!" if args.all?
    end

    targets = if args.all?
      Service::Formulae.available_services
    elsif formula
      [Service::FormulaWrapper.new(Formulary.factory(formula))]
    else
      []
    end

    ENV["DBUS_SESSION_BUS_ADDRESS"] = ENV["HOMEBREW_DBUS_SESSION_BUS_ADDRESS"] if Service::System.systemctl?

    # Dispatch commands and aliases.
    case subcommand.presence
    when *Service::Commands::List::TRIGGERS
      Service::Commands::List.run(json: args.json?)
    when *Service::Commands::Cleanup::TRIGGERS
      Service::Commands::Cleanup.run
    when *Service::Commands::Info::TRIGGERS
      Service::Commands::Info.run(targets, verbose: args.verbose?, json: args.json?)
    when *Service::Commands::Restart::TRIGGERS
      Service::Commands::Restart.run(targets, custom_plist, verbose: args.verbose?)
    when *Service::Commands::Run::TRIGGERS
      Service::Commands::Run.run(targets, verbose: args.verbose?)
    when *Service::Commands::Start::TRIGGERS
      Service::Commands::Start.run(targets, custom_plist, verbose: args.verbose?)
    when *Service::Commands::Stop::TRIGGERS
      Service::Commands::Stop.run(targets, verbose: args.verbose?)
    when *Service::Commands::Kill::TRIGGERS
      Service::Commands::Kill.run(targets, verbose: args.verbose?)
    else
      raise UsageError, "unknown subcommand: `#{subcommand}`"
    end
  end
end
