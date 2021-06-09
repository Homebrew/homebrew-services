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

    # Current user running `[sudo] brew services`.
    def user
      @user ||= Utils.safe_popen_read("/usr/bin/whoami").chomp
    end

    def user_of_process(pid)
      if pid.nil? || pid.zero?
        ENV["HOME"].split("/").last
      else
        Utils.safe_popen_read("ps", "-o", "user", "-p", pid.to_s).lines.second.chomp
      end
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
      Utils.popen_read("#{launchctl} list | grep homebrew").chomp.split("\n").map do |svc|
        Regexp.last_match(1) if svc =~ /(homebrew\.mxcl\..+)\z/
      end.compact
    end

    # All available services
    def available_services
      require "formula"

      Formula.installed.map { |formula| Service.new(formula) }.select(&:plist?).sort_by(&:name)
    end

    def domain_target
      if root?
        "system"
      else
        "gui/#{Process.uid}"
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

        if service.plist_present?(for: :root)
          formula[:status] = :started
          formula[:user] = "root"
          formula[:plist] = ServicesCli.boot_path + service.plist.basename
        elsif service.plist_present?(for: :user)
          formula[:status] = :started
          formula[:user] = ServicesCli.user_of_process(service.pid)
          formula[:plist] = ServicesCli.user_path + service.plist.basename
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
        when :unknown then "#{Tty.yellow}unknown#{Tty.reset}"
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
      Dir["#{path}homebrew.*.{plist,service}"].each do |file|
        next if running.include?(File.basename(file).sub(/\.(plist|service)$/i, ""))

        puts "Removing unused plist #{file}"
        rm file
        cleaned << file
      end

      puts "All #{root? ? "root" : "user-space"} services OK, nothing cleaned..." if cleaned.empty?
    end

    # Stop if loaded, then start or run again.
    def restart(target, plist_file = nil, verbose: false)
      Array(target).each do |service|
        was_run = service.loaded? && !service.plist_present?

        stop(service) if service.loaded?

        if was_run
          run(service)
        else
          start(service, plist_file, verbose: verbose)
        end
      end
    end

    # Run a service as defined in the formula. This does not clean the plist like `start` does.
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
        launchctl_load(service, enable: false)
      end
    end

    # Start a service.
    def start(target, plist_file = nil, verbose: false)
      if plist_file.present?
        @plist = Pathname.new plist_file
        raise UsageError, "Provided plist does not exist" unless @plist.exist?
      end
      if target.is_a?(Service)
        if target.loaded?
          puts "Service `#{target.name}` already started, use `#{bin} restart #{target.name}` to restart."
          return
        end

        if !target.installed?
          odie "Formula `#{target.name}` is not installed."
        elsif !target.plist.file? && target.formula.plist.nil?
          if target.formula.opt_prefix.exist? &&
             (keg = Keg.for target.formula.opt_prefix) &&
             keg.plist_installed?
            @plist ||= Pathname.new Dir["#{keg}/*.{plist,service}"].first
          else
            odie "Formula `#{target.name}` has not implemented #plist or installed a locatable .plist file"
          end
        end
      end

      Array(target).reject(&:loaded?).each do |service|
        install_service_file(service) if @plist.blank?

        if @plist.blank? && verbose
          ohai "Generated plist for #{service.formula.name}:"
          puts "   #{service.dest.read.gsub("\n", "\n   ")}"
          puts
        end

        next if take_root_ownership(service).nil? && root?

        launchctl_load(service, enable: true)
      end
    end

    # Stop a service, or kill it if no plist file is available.
    def stop(target)
      if target.is_a?(Service) && !target.loaded?
        rm target.dest if target.dest.exist? # get rid of installed plist anyway, dude
        if target.plist_present?
          odie <<~EOS
            Service `#{target.name}` is started as `#{target.owner}`. Try:
              #{"sudo " unless ServicesCli.root?}#{bin} stop #{target.name}
          EOS
        else
          odie "Service `#{target.name}` is not started."
        end
      end

      Array(target).select(&:loaded?).each do |service|
        puts "Stopping `#{service.name}`... (might take a while)"
        quiet_system launchctl, "bootout", "#{domain_target}/#{service.label}"
        while $CHILD_STATUS.to_i == 9216 || service.loaded?
          sleep(1)
          quiet_system launchctl, "bootout", "#{domain_target}/#{service.label}"
        end
        if service.dest.exist?
          ohai "Successfully stopped `#{service.name}` (label: #{service.label})"
        elsif service.loaded?
          kill(service)
        end
        rm service.dest if service.dest.exist?
      end
    end

    # Kill a service that has no plist file.
    def kill(service)
      quiet_system launchctl, "kill", "SIGTERM", "#{domain_target}/#{service.label}"
      while service.loaded?
        sleep(5)
        break if service.loaded?

        quiet_system launchctl, "kill", "SIGKILL", "#{domain_target}/#{service.label}"
      end
      ohai "Successfully stopped `#{service.name}` via #{service.label}"
    end

    def install_service_file(service)
      temp = Tempfile.new(service.label)
      temp << service.generate_plist(@plist)
      temp.flush

      rm service.dest if service.dest.exist?
      service.dest_dir.mkpath unless service.dest_dir.directory?
      cp temp.path, service.dest

      # Clear tempfile.
      temp.close

      chmod 0644, service.dest
    end

    # protections to avoid users editing root services
    def take_root_ownership(service)
      return unless root?

      chown "root", "admin", service.dest
      plist_data = service.dest.read
      plist = begin
        Plist.parse_xml(plist_data)
      rescue
        nil
      end
      return unless plist

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

    def launchctl_load(service, enable:)
      if root? && !service.plist_startup?
        opoo "#{service.name} must be run as non-root to start at user login!"
      elsif !root? && service.plist_startup?
        opoo "#{service.name} must be run as root to start at system startup!"
      end

      @plist ||= enable ? service.dest : service.plist

      safe_system launchctl, "enable", "#{domain_target}/#{service.label}" if enable
      safe_system launchctl, "bootstrap", domain_target, @plist

      function = enable ? "started" : "ran"
      ohai("Successfully #{function} `#{service.name}` (label: #{service.label})")
    end
  end
end
