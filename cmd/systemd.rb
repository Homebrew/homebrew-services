#:  * `services`
#:    Easily start and stop formulae via systemd
#:
#:    Integrates Homebrew formulae with `systemd` manager. Services can be
#:    added to either `/etc/systemd/system` or `~/.config/systemd/user`.
#:    Basically, items in `/etc/systemd/system` are started at boot, while those
#:    in `~/.config/systemd/user` are started at login.
#:
#:    When started with `sudo`, it operates on `/etc/systemd/system`; otherwise,
#:    it operates on `~/.config/systemd/user`.
#:
#:    On `start` the service file is generated and written to a `Tempfile`, and then
#:    copied to the launch path (existing services are overwritten).
#:
#:    [<sudo>] `brew services` `list`
#:    List all running services for the current user (or <root>)
#:
#:    [<sudo>] `brew services` `run` <formula|--all>
#:    Run the service <formula> without starting at login (or boot).
#:
#:    [<sudo>] `brew services` `start` <formula|--all>
#:    Install and start the service <formula> at login (or <boot>).
#:
#:    [<sudo>] `brew services` `stop` <formula|--all>
#:    Stop the service <formula> after it was launched at login (or <boot>).
#:
#:    [<sudo>] `brew services` `restart` <formula|--all>
#:    Stop (if necessary), install and start the service <formula> at login (or <boot>).
#:
#:    [<sudo>] `brew services` `cleanup`
#:    Remove all unused services.

module ServicesCli
  class << self
    # Binary name.
    def bin
      "brew services"
    end

    # Path to systemctl binary.
    def systemctl
      cmd = which("systemctl")
      root? ? cmd : "#{cmd} --user"
    end

    # Woohoo, we are root dude!
    def root?
      Process.uid.zero?
    end

    # Current user, i.e., owner of `HOMEBREW_CELLAR`.
    def user
      @user ||= `/usr/bin/stat -c '%U' #{HOMEBREW_CELLAR} 2>/dev/null`.chomp || `/usr/bin/whoami`.chomp
    end

    # Run at boot.
    def boot_path
      Pathname.new("/etc/systemd/system")
    end

    # Run at login.
    def user_path
      Pathname.new(File.join(ENV["HOME"], "/.config/systemd/user"))
    end

    # If root, return `boot_path`, else return `user_path`.
    def path
      root? ? boot_path : user_path
    end

    # Find all currently running services via systemctl
    def running
      `#{systemctl} list-units --no-legend --state=running`.chomp.split("\n").map { |svc| $1 if svc =~ /(homebrew\.mxcl\.[^s]+)\z/ }.compact
    end

    # Check if running as Homebrew and load required libraries, et al.
    def homebrew!
      abort("Runtime error: Homebrew is required. Please start via `#{bin} ...`") unless defined?(HOMEBREW_LIBRARY_PATH)
      %w[fileutils pathname tempfile formula utils].each { |req| require(req) }
      extend(FileUtils)
    end

    # All available services
    def available_services
      Formula.installed.map { |formula| Service.new(formula) }.select(&:systemd?)
    end

    # Run and start the command loop.
    def run!
      homebrew!

      quiet_system("#{systemctl} daemon-reload")

      # pbpaste's exit status is a proxy for detecting the use of reattach-to-user-namespace
      # FIXME not sure what to do with this on linux yet
      # if ENV["TMUX"] && !quiet_system("/usr/bin/pbpaste")
      #   odie "brew services cannot run under tmux!"
      # end

      # Parse arguments.
      act_on_all_services = ARGV.include?("--all")
      cmd = ARGV.named[0]
      formula = ARGV.named[1]
      custom_service_file = ARGV.named[2]

      target = if act_on_all_services
        available_services
      elsif formula
        Service.new(Formulary.factory(formula))
      end

      # Dispatch commands and aliases.
      case cmd
      when "cleanup", "clean", "cl", "rm" then cleanup
      when "list", "ls" then list
      when "restart", "relaunch", "reload", "r" then check(target) && restart(target)
      when "run" then check(target) && run(target)
      when "start", "launch", "load", "s", "l" then check(target) && start(target, custom_service_file)
      when "stop", "unload", "terminate", "term", "t", "u" then check(target) && stop(target)
      else
        onoe "Unknown command `#{cmd}`!" unless cmd.nil?
        abort `brew services --help`
      end
    ensure
      quiet_system("#{systemctl} daemon-reload")
    end

    # Check if formula has been found.
    def check(target)
      odie("Formula(e) missing, please provide a formula name or use --all") unless target
      true
    end

    # List all available services with status, user, and path to the service file.
    def list
      formulae = available_services.map do |service|
        formula = {
          name: service.formula.name,
          status: :stopped,
          user: nil,
          service_file: nil,
        }

        # Check the exit code of the service, might indicate an error
        if service.loaded?
          formula[:user] = ServicesCli.user
          formula[:service_file] = File.join(ServicesCli.path, "#{service.label}.service")

          if service.unknown_status?
            formula[:status] = :unknown
          elsif service.error?
            formula[:status] = :error
          elsif service.started?
            formula[:status] = :started
          end
        end

        formula
      end

      if formulae.empty?
        odie "No services available to control with `#{bin}`"
      end

      longest_name = [formulae.max_by { |formula| formula[:name].length }[:name].length, 4].max
      longest_user = [formulae.map { |formula| formula[:user].nil? ? 4 : formula[:user].length }.max, 4].max

      puts format("#{Tty.white}%-#{longest_name}.#{longest_name}s %-7.7s %-#{longest_user}.#{longest_user}s %s#{Tty.reset}",
                  "Name", "Status", "User", "Service")
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

        puts format("%-#{longest_name}.#{longest_name}s %s %-#{longest_user}.#{longest_user}s %s",
                    formula[:name],
                    status,
                    formula[:user],
                    formula[:service_file])
      end
    end

    # Kill services that don't have a service file, and remove unused service files.
    def cleanup
      cleaned = []

      # 1. Kill services that don't have a service file.
      running.each do |label|
        if svc = Service.from(label)
          unless svc.dest.file?
            puts format("%-15.15s #{Tty.white}stale#{Tty.reset} => killing service...", svc.name)
            kill(svc)
            cleaned << label
          end
        else
          opoo "Service #{label} not managed by `#{bin}` => skipping"
        end
      end

      # 2. Remove unused service files.
      Dir[path + "homebrew.mxcl.*.service"].each do |file|
        next if running.include?(File.basename(file).sub(/\.service$/i, ""))
        puts "Removing unused service #{file}"
        rm file
        cleaned << file
      end

      puts "All #{root? ? "root" : "user-space"} services OK, nothing cleaned..." if cleaned.empty?
    end

    # Stop if loaded, then start or run again.
    def restart(target)
      Array(target).each do |service|
        was_run = service.loaded? && !service.started?

        stop(service) if service.loaded?

        if was_run
          run(service)
        else
          start(service)
        end
      end
    end

    # Run a service.
    def run(target)
      if target.is_a?(Service) && target.loaded?
        puts "Service `#{target.name}` already running, use `#{bin} restart #{target.name}` to restart."
        return
      end

      Array(target).each do |service|
        safe_system("#{systemctl} start #{service.service_file}")

        if $?.to_i.nonzero?
          odie("Failed to start `#{service.name}`")
        else
          ohai("Successfully started `#{service.name}` (label: #{service.label})")
        end
      end
    end

    # Start a service.
    def start(target, custom_service_file = nil)
      if target.is_a?(Service)
        if target.loaded?
          odie "Service `#{target.name}` already started, use `#{bin} restart #{target.name}` to restart."
        end

        if custom_service_file
          if custom_service_file =~ %r{\Ahttps?://.+}
            custom_service_file = { url: custom_service_file }
          elsif File.exist?(custom_service_file)
            custom_service_file = Pathname.new(custom_service_file)
          else
            odie "#{custom_service_file} is not a url or existing file"
          end
        elsif !target.installed?
          odie "Formula `#{target.name}` is not installed."
        elsif target.service_file.file?
          custom_service_file = target.service_file
        elsif target.formula.respond_to?(:systemd) && !target.formula.systemd.nil?
          custom_service_file = target.formula.systemd
        else
          odie "Formula `#{target.name}` has not implemented #systemd or installed a locatable .service file"
        end
      end

      Array(target).each do |service|
        temp = Tempfile.new(service.label)
        temp << service.generate_service_file(custom_service_file)
        temp.flush

        rm service.dest if service.dest.exist?
        service.dest_dir.mkpath unless service.dest_dir.directory?
        cp temp.path, service.dest

        # Clear tempfile.
        temp.close

        quiet_system("#{systemctl} daemon-reload")
        quiet_system("#{systemctl} enable #{service.dest.basename}")
        quiet_system("#{systemctl} start #{service.dest.basename}")

        if $?.to_i.nonzero?
          odie("Failed to start `#{service.name}`")
        else
          ohai("Successfully started `#{service.name}` (label: #{service.label})")
        end
      end
    end

    # Stop a service, or kill it if no service file is available.
    def stop(target)
      if target.is_a?(Service)
        odie "#{target.name} is not loaded" unless target.loaded?
        rm target.dest if target.dest.exist? # get rid of installed service anyway
        odie "Service `#{target.name}` is not started."  unless target.started?
        unless quiet_system("#{systemctl} stop #{target.label}.service") &&
          quiet_system("#{systemctl} disable #{target.label}.service")
          opoo "had trouble stopping #{target.name}. Trying to kill..."
          kill(target)
        end
      elsif target.is_a?(Array)
        puts "array. stopping all #{target.length}.."
        Array(target).select(&:loaded?).each do |service|
          stop(service)
        end
      end

    end

    # Kill a service that has no service file by issuing `service remove`.
    def kill(svc)
      if safe_system("#{systemctl} kill #{svc.label}")
        ohai "Successfully killed `#{svc.name}` via #{svc.label}"
      else
        odie("Failed to remove `#{svc.name}`, try again?")
      end
    end
  end
end

# Wrapper for a formula to handle service-related stuff like parsing and
# generating the service file.
class Service
  # Access the `Formula` instance.
  attr_reader :formula

  # Create a new `Service` instance from either a path or label.
  def self.from(path_or_label)
    return unless path_or_label =~ /homebrew\.mxcl\.([\w+-.@]+)(\.service)?\z/
    begin
      new(Formulary.factory($1))
    rescue
      nil
    end
  end

  # Initialize a new `Service` instance with supplied formula.
  def initialize(formula)
    @formula = formula
  end

  # Delegate access to `formula.name`.
  def name
    @name ||= formula.name
  end

  # Label delegates with formula.plist_name (e.g., `homebrew.mxcl.<formula>`).
  def label
    @label ||= formula.plist_name
  end

  # Path to a static service file. This is always `homebrew.mxcl.<formula>.service`.
  def service_file
    @service_file ||= formula.opt_prefix + "#{label}.service"
  end

  # Path to destination service directory. If run as root, it's `boot_path`, else `user_path`.
  def dest_dir
    ServicesCli.root? ? ServicesCli.boot_path : ServicesCli.user_path
  end

  # Path to destination service. If run as root, it's in `boot_path`, else `user_path`.
  def dest
    Pathname.new(File.join(dest_dir, "#{label}.service"))
  end

  # Returns `true` if any version of the formula is installed.
  def installed?
    formula.installed? || ((dir = formula.opt_prefix).directory? && !dir.children.empty?)
  end

  # Returns `true` if the formula implements #systemd or the .service file exists.
  def systemd?
    return false unless @formula.respond_to?(:systemd)
    return false unless installed?
    return true if service_file.file?
    return true unless formula.systemd.nil?
    return false unless formula.opt_prefix.exist?
    return true if Keg.for(formula.opt_prefix).service_installed?
  rescue NotAKegError
    false
  end

  # Returns `true` if the service is loaded, else false.
  def loaded?
    `#{ServicesCli.systemctl} --type service --no-legend --quiet list-units #{label}.service`.chomp.include? "loaded"
  end

  # Returns `true` if service is started, else `false`
  # Accepts Hash option `:as` with values `:root` for /etc/systemd/system path or `:user` for ~/.config/systemd/user path.
  def started?(opts = { as: false })
    status == "active"
  end

  def error?
    # systemctl is-failed exits 0 if the service failed
    quiet_system("#{ServicesCli.systemctl} is-failed --quiet #{label}.service")
  end

  def unknown_status?
    status == "unknown"
  end

  # Get current PID of daemon process from systemctl.
  def pid
    # returns 0 even if the label isn't known
    safe_system("#{ServicesCli.systemctl} show -p MainPID #{label}.service").chomp.split("=")[1].to_i
  end

  def exit_code
    # returns 0 even if the label isn't known
    safe_system("#{ServicesCli.systemctl} show -p ExecMainCode #{label}.service").chomp.split("=")[1].to_i
  end

  # Generate that service file, dude.
  def generate_service_file(data = nil)
    data ||= service_file.file? ? service_file : formula.systemd

    if data.respond_to?(:file?) && data.file?
      data = data.read
    elsif data.respond_to?(:keys) && data.keys.include?(:url)
      require "open-uri"
      data = open(data).read
    elsif !data
      odie "Could not read the service for `#{name}`!"
    end

    # Replace "template" variables and ensure label is always, always homebrew.mxcl.<formula>
    data = data.to_s.gsub(/\{\{([a-z][a-z0-9_]*)\}\}/i) { |_m| formula.send($1).to_s if formula.respond_to?($1) }.gsub(%r{(<key>Label</key>\s*<string>)[^<]*(</string>)}, '\1' + label + '\2')

    # Always remove the "User" as it doesn't work since 10.11.5
    if data.include? "User="
      data = data.gsub(%r{User=.*$}, "")
    end

    if ARGV.verbose?
      ohai "Generated service for #{formula.name}:"
      puts "   " + data.gsub("\n", "\n   ")
      puts
    end

    data
  end

  def status
    `#{ServicesCli.systemctl} show --no-legend -p ActiveState #{label}.service 2>/dev/null`.chomp.split("=")[1] rescue "unknown"
  end

end
