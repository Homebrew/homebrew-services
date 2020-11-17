# frozen_string_literal: true

require_relative "service"

module Homebrew
  module ServicesCli
    extend FileUtils

    module_function

    # Binary name.
    def bin
      "brew services"
    end

    # Path to launchctl binary.
    def launchctl
      which("launchctl")
    end

    # Woohoo, we are root dude!
    def root?
      Process.uid.zero?
    end

    # Current user.
    def user
      @user ||= `/usr/bin/whoami`.chomp
    end

    # Run at boot.
    def boot_path
      Pathname.new("/Library/LaunchDaemons")
    end

    # Run at login.
    def user_path
      Pathname.new("#{ENV["HOME"]}/Library/LaunchAgents")
    end

    # If root, return `boot_path`, else return `user_path`.
    def path
      root? ? boot_path : user_path
    end

    # Find all currently running services via launchctl list.
    def running
      # TODO: find replacement for deprecated "list"
      `#{launchctl} list | grep homebrew.mxcl`.chomp.split("\n").map do |svc|
        Regexp.last_match(1) if svc =~ /(homebrew\.mxcl\..+)\z/
      end.compact
    end

    # All available services
    def available_services
      require "formula"

      Formula.installed.map { |formula| Service.new(formula) }.select(&:plist?).sort_by(&:name)
    end

    # Run and start the command loop.
    def run!(args)
      # pbpaste's exit status is a proxy for detecting the use of reattach-to-user-namespace
      raise UsageError, "brew services cannot run under tmux!" if ENV["TMUX"] && !quiet_system("/usr/bin/pbpaste")

      # Parse arguments.
      subcommand, formula, custom_plist, = args.named

      if ["list", "cleanup"].include?(subcommand)
        raise UsageError, "The `#{subcommand}` subcommand does not accept a formula argument!" if formula
        raise UsageError, "The `#{subcommand}` subcommand does not accept the --all argument!" if args.all?
      end

      target = if args.all?
        available_services
      elsif formula
        Service.new(Formulary.factory(formula))
      end

      # Dispatch commands and aliases.
      case subcommand.presence
      when nil, "list", "ls" then list
      when "cleanup", "clean", "cl", "rm" then cleanup
      when "restart", "relaunch", "reload", "r" then check(target) && restart(target, custom_plist, args: args)
      when "run" then check(target) && run(target)
      when "start", "launch", "load", "s", "l" then check(target) && start(target, custom_plist, args: args)
      when "stop", "unload", "terminate", "term", "t", "u" then check(target) && stop(target)
      else
        raise UsageError, "unknown subcommand: #{subcommand}"
      end
    end

    # Check if formula has been found.
    def check(target)
      odie("Formula(e) missing, please provide a formula name or use --all") unless target
      true
    end

    # List all available services with status, user, and path to the plist file.
    def list
      formulae = available_services.map do |service|
        formula = {
          name:   service.formula.name,
          status: :stopped,
          user:   nil,
          plist:  nil,
        }

        if service.started?(as: :root)
          formula[:status] = :started
          formula[:user] = "root"
          formula[:plist] = ServicesCli.boot_path + "#{service.label}.plist"
        elsif service.started?(as: :user)
          formula[:status] = :started
          formula[:user] = ServicesCli.user
          formula[:plist] = ServicesCli.user_path + "#{service.label}.plist"
        elsif service.loaded?
          formula[:status] = :started
          formula[:user] = ServicesCli.user
          formula[:plist] = service.plist
        end

        # Check the exit code of the service, might indicate an error
        if formula[:status] == :started
          if service.unknown_status?
            formula[:status] = :unknown
          elsif service.error?
            formula[:status] = :error
          end
        end

        formula
      end

      if formulae.empty?
        opoo("No services available to control with `#{bin}`")
        return
      end

      longest_name = [formulae.max_by { |formula| formula[:name].length }[:name].length, 4].max
      longest_user = [formulae.map { |formula| formula[:user].nil? ? 4 : formula[:user].length }.max, 4].max

      puts format("#{Tty.bold}%-#{longest_name}.#{longest_name}<name>s %-7.7<status>s " \
                  "%-#{longest_user}.#{longest_user}<user>s %<plist>s#{Tty.reset}",
                  name:   "Name",
                  status: "Status",
                  user:   "User",
                  plist:  "Plist")
      formulae.each do |formula|
        status = case formula[:status]
        when :started then "#{Tty.green}started#{Tty.reset}"
        when :stopped then "stopped"
        when :error   then "#{Tty.red}error  #{Tty.reset}"
        when :unknown
          if ENV["HOMEBREW_DEVELOPER"]
            "#{Tty.yellow}unknown#{Tty.reset}"
          else
            # For backwards-compatability showing unknown state as started in yellow colour
            "#{Tty.yellow}started#{Tty.reset}"
          end
        end

        puts format("%-#{longest_name}.#{longest_name}<name>s %<status>s " \
                    "%-#{longest_user}.#{longest_user}<user>s %<plist>s",
                    name:   formula[:name],
                    status: status,
                    user:   formula[:user],
                    plist:  formula[:plist])
      end
    end

    # Kill services that don't have a plist file, and remove unused plist files.
    def cleanup
      cleaned = []

      # 1. Kill services that don't have a plist file.
      running.each do |label|
        if (svc = Service.from(label))
          unless svc.dest.file?
            puts format("%-15.15<name>s #{Tty.bold}stale#{Tty.reset} => killing service...", name: svc.name)
            kill(svc)
            cleaned << label
          end
        else
          opoo "Service #{label} not managed by `#{bin}` => skipping"
        end
      end

      # 2. Remove unused plist files.
      Dir["#{path}homebrew.mxcl.*.plist"].each do |file|
        next if running.include?(File.basename(file).sub(/\.plist$/i, ""))

        puts "Removing unused plist #{file}"
        rm file
        cleaned << file
      end

      puts "All #{root? ? "root" : "user-space"} services OK, nothing cleaned..." if cleaned.empty?
    end

    # Stop if loaded, then start or run again.
    def restart(target, custom_plist = nil, args:)
      Array(target).each do |service|
        was_run = service.loaded? && !service.started?

        stop(service) if service.loaded?

        if was_run
          run(service)
        else
          start(service, custom_plist, args: args)
        end
      end
    end

    def domain_target
      if root?
        "system"
      else
        "gui/#{Process.uid}"
      end
    end

    def launchctl_load(plist, function, service)
      if root? && !service.plist_startup?
        opoo "#{service.name} must be run as non-root to start at user login!"
      elsif !root? && service.plist_startup?
        opoo "#{service.name} must be run as root to start at system startup!"
      end

      if MacOS.version >= :yosemite
        safe_system launchctl, "enable", "#{domain_target}/#{service.label}" if function != "ran"
        safe_system launchctl, "bootstrap", domain_target, plist
      else
        # This syntax was deprecated in Yosemite
        safe_system launchctl, "load", "-w", plist
      end

      ohai("Successfully #{function} `#{service.name}` (label: #{service.label})")
    end

    # Run a service.
    def run(target)
      if target.is_a?(Service)
        if target.loaded?
          puts "Service `#{target.name}` already running, use `#{bin} restart #{target.name}` to restart."
          return
        elsif root?
          puts "Service `#{target.name}` cannot be run (but can be started) as root."
          return
        end
      end

      Array(target).each do |service|
        launchctl_load(service.plist, "ran", service)
      end
    end

    # Start a service.
    def start(target, custom_plist = nil, args:)
      if target.is_a?(Service)
        if target.loaded?
          puts "Service `#{target.name}` already started, use `#{bin} restart #{target.name}` to restart."
          return
        end

        if custom_plist
          if %r{\Ahttps?://.+}.match?(custom_plist)
            custom_plist = { url: custom_plist }
          elsif File.exist?(custom_plist)
            custom_plist = Pathname.new(custom_plist)
          else
            odie "#{custom_plist} is not a URL or existing file"
          end
        elsif !target.installed?
          odie "Formula `#{target.name}` is not installed."
        elsif !target.plist.file? && target.formula.plist.nil?
          if target.formula.opt_prefix.exist? &&
             (keg = Keg.for target.formula.opt_prefix) &&
             keg.plist_installed?
            custom_plist = Pathname.new Dir["#{keg}/*.plist"].first
          else
            odie "Formula `#{target.name}` has not implemented #plist or installed a locatable .plist file"
          end
        end
      end

      Array(target).reject(&:loaded?).each do |service|
        temp = Tempfile.new(service.label)
        temp << service.generate_plist(custom_plist, args: args)
        temp.flush

        rm service.dest if service.dest.exist?
        service.dest_dir.mkpath unless service.dest_dir.directory?
        cp temp.path, service.dest

        # Clear tempfile.
        temp.close

        chmod 0644, service.dest

        if root?
          chown "root", "admin", service.dest
          plist_data = service.dest.read
          plist = begin
            Plist.parse_xml(plist_data)
          rescue
            nil
          end
          next unless plist

          root_paths = []

          program_location = plist["ProgramArguments"]&.first
          key = "first ProgramArguments value"
          if program_location.blank?
            program_location = plist["Program"]
            key = "Program"
          end

          if program_location.present?
            Dir.chdir("/") do
              if File.exist?(program_location)
                program_location_path = Pathname(program_location).realpath
                root_paths += [
                  program_location_path,
                  program_location_path.parent.realpath,
                ]
              else
                opoo <<~EOS
                  #{service.name}: the #{key} does not exist:
                    #{program_location}
                EOS
              end
            end
          end
          if (formula = service.formula)
            root_paths += [
              formula.opt_prefix,
              formula.linked_keg,
              formula.bin,
              formula.sbin,
            ]
          end
          root_paths = root_paths.sort.uniq.select(&:exist?)

          opoo <<~EOS
            Taking root:admin ownership of some #{service.formula} paths:
              #{root_paths.join("\n  ")}
            This will require manual removal of these paths using `sudo rm` on
            brew upgrade/reinstall/uninstall.
          EOS
          chown "root", "admin", root_paths
          chmod "+t", root_paths
        end

        launchctl_load(service.dest.to_s, "started", service)
      end
    end

    # Stop a service, or kill it if no plist file is available.
    def stop(target)
      if target.is_a?(Service) && !target.loaded?
        rm target.dest if target.dest.exist? # get rid of installed plist anyway, dude
        if target.started?
          odie <<~EOS
            Service `#{target.name}` is started as `#{target.started_as}`. Try:
              #{"sudo " unless ServicesCli.root?}#{bin} stop #{target.name}
          EOS
        else
          odie "Service `#{target.name}` is not started."
        end
      end

      Array(target).select(&:loaded?).each do |service|
        puts "Stopping `#{service.name}`... (might take a while)"
        # This command doesn't exist in Yosemite.
        if MacOS.version >= :el_capitan
          quiet_system launchctl, "bootout", "#{domain_target}/#{service.label}"
          while $CHILD_STATUS.to_i == 9216
            sleep(5)
            quiet_system launchctl, "bootout", "#{domain_target}/#{service.label}"
          end
        end
        if service.dest.exist?
          unless MacOS.version >= :el_capitan
            # This syntax was deprecated in Yosemite but there's no alternative
            # command (bootout) until El Capitan.
            safe_system launchctl, "unload", "-w", service.dest.to_s
          end
          ohai "Successfully stopped `#{service.name}` (label: #{service.label})"
        elsif service.loaded?
          kill(service)
        end
        rm service.dest if service.dest.exist?
      end
    end

    # Kill a service that has no plist file.
    def kill(service)
      if MacOS.version >= :yosemite
        quiet_system launchctl, "kill", "SIGTERM", "#{domain_target}/#{service.label}"
      else
        safe_system launchctl, "remove", service.label
      end
      while service.loaded?
        sleep(5)
        break if service.loaded?

        quiet_system launchctl, "kill", "SIGKILL", "#{domain_target}/#{service.label}" if MacOS.version >= :yosemite
      end
      ohai "Successfully stopped `#{service.name}` via #{service.label}"
    end
  end
end
