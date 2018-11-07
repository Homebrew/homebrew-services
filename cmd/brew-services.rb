#:  * `services` <command>:
#:    Integrates Homebrew formulae with macOS' `launchctl` manager.
#:
#:    [`sudo`] `brew services list`:
#:    List all running services for the current user (or root).
#:
#:    [`sudo`] `brew services run` (<formula>|`--all`):
#:    Run the service <formula> without registering to launch at login (or boot).
#:
#:    [`sudo`] `brew services start` (<formula>|`--all`):
#:    Start the service <formula> immediately and register it to launch at login (or boot).
#:
#:    [`sudo`] `brew services stop` (<formula>|`--all`):
#:    Stop the service <formula> immediately and unregister it from launching at login (or boot).
#:
#:    [`sudo`] `brew services restart` (<formula>|`--all`):
#:    Stop (if necessary) and start the service <formula> immediately and register it to launch at login (or boot).
#:
#:    [`sudo`] `brew services cleanup`:
#:    Remove all unused services.
#:
#:    If `sudo` is passed, operate on `/Library/LaunchDaemons` (started at boot).
#:    Otherwise, operate on `~/Library/LaunchAgents` (started at login).

unless defined? HOMEBREW_LIBRARY_PATH
  abort "Runtime error: Homebrew is required. Please start via `#{bin} ...`"
end

# TODO: refactor into multiple modules
module ServicesCli # rubocop:disable Metrics/ModuleLength
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
    Pathname.new(ENV["HOME"] + "/Library/LaunchAgents")
  end

  # If root, return `boot_path`, else return `user_path`.
  def path
    root? ? boot_path : user_path
  end

  # Find all currently running services via launchctl list.
  def running
    # TODO: find replacement for deprecated "list"
    `#{launchctl} list | grep homebrew.mxcl`.chomp.split("\n").map { |svc| Regexp.last_match(1) if svc =~ /(homebrew\.mxcl\..+)\z/ }.compact
  end

  # All available services
  def available_services
    Formula.installed.map { |formula| Service.new(formula) }.select(&:plist?).sort_by(&:name)
  end

  # Run and start the command loop.
  def run!
    # pbpaste's exit status is a proxy for detecting the use of reattach-to-user-namespace
    if ENV["TMUX"] && !quiet_system("/usr/bin/pbpaste")
      odie "brew services cannot run under tmux!"
    end

    # Parse arguments.
    act_on_all_services = ARGV.include?("--all")
    cmd = ARGV.named[0]
    formula = ARGV.named[1]
    custom_plist = ARGV.named[2]

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
    when "start", "launch", "load", "s", "l" then check(target) && start(target, custom_plist)
    when "stop", "unload", "terminate", "term", "t", "u" then check(target) && stop(target)
    else
      onoe "Unknown command `#{cmd}`!" unless cmd.nil?
      abort `brew services --help`
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

    puts format("#{Tty.bold}%-#{longest_name}.#{longest_name}{name} %-7.7{status} " \
                "%-#{longest_user}.#{longest_user}{user} %{plist}#{Tty.reset}",
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

      puts format("%-#{longest_name}.#{longest_name}{name} %{status} " \
                  "%-#{longest_user}.#{longest_user}{user} %{plist}",
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
      if svc = Service.from(label)
        unless svc.dest.file?
          puts format("%-15.15s #{Tty.bold}stale#{Tty.reset} => killing service...", svc.name)
          kill(svc)
          cleaned << label
        end
      else
        opoo "Service #{label} not managed by `#{bin}` => skipping"
      end
    end

    # 2. Remove unused plist files.
    Dir[path + "homebrew.mxcl.*.plist"].each do |file|
      next if running.include?(File.basename(file).sub(/\.plist$/i, ""))
      puts "Removing unused plist #{file}"
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

  def domain_target
    if root?
      "system"
    else
      "gui/#{Process.uid}"
    end
  end

  def launchctl_load(plist, function, service)
    if MacOS.version >= :yosemite
      unless function == "ran"
        safe_system launchctl, "enable", "#{domain_target}/#{service.label}"
      end
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
  def start(target, custom_plist = nil)
    if target.is_a?(Service)
      if target.loaded?
        puts "Service `#{target.name}` already started, use `#{bin} restart #{target.name}` to restart."
        return
      end

      if custom_plist
        if custom_plist =~ %r{\Ahttps?://.+}
          custom_plist = { url: custom_plist }
        elsif File.exist?(custom_plist)
          custom_plist = Pathname.new(custom_plist)
        else
          odie "#{custom_plist} is not a url or existing file"
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
      temp << service.generate_plist(custom_plist)
      temp.flush

      rm service.dest if service.dest.exist?
      service.dest_dir.mkpath unless service.dest_dir.directory?
      cp temp.path, service.dest
      chmod 0644, service.dest

      # Clear tempfile.
      temp.close

      launchctl_load(service.dest.to_s, "started", service)
    end
  end

  # Stop a service, or kill it if no plist file is available.
  def stop(target)
    if target.is_a?(Service) && !target.loaded?
      rm target.dest if target.dest.exist? # get rid of installed plist anyway, dude
      if target.started?
        odie "Service `#{target.name}` is started as `#{target.started_as}`. Try `#{"sudo " unless ServicesCli.root?}#{bin} stop #{target.name}`"
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
      if MacOS.version >= :yosemite
        quiet_system launchctl, "kill", "SIGKILL", "#{domain_target}/#{service.label}"
      end
    end
    ohai "Successfully stopped `#{service.name}` via #{service.label}"
  end
end

# Wrapper for a formula to handle service-related stuff like parsing and
# generating the plist file.
class Service
  # Access the `Formula` instance.
  attr_reader :formula

  # Create a new `Service` instance from either a path or label.
  def self.from(path_or_label)
    return unless path_or_label =~ /homebrew\.mxcl\.([\w+-.@]+)(\.plist)?\z/
    begin
      new(Formulary.factory(Regexp.last_match(1)))
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

  # Path to a static plist file. This is always `homebrew.mxcl.<formula>.plist`.
  def plist
    @plist ||= formula.opt_prefix + "#{label}.plist"
  end

  # Path to destination plist directory. If run as root, it's `boot_path`, else `user_path`.
  def dest_dir
    ServicesCli.root? ? ServicesCli.boot_path : ServicesCli.user_path
  end

  # Path to destination plist. If run as root, it's in `boot_path`, else `user_path`.
  def dest
    dest_dir + "#{label}.plist"
  end

  # Returns `true` if any version of the formula is installed.
  def installed?
    formula.installed? || ((dir = formula.opt_prefix).directory? && !dir.children.empty?)
  end

  # Returns `true` if the formula implements #plist or the plist file exists.
  def plist?
    return false unless installed?
    return true if plist.file?
    return true unless formula.plist.nil?
    return false unless formula.opt_prefix.exist?
    return true if Keg.for(formula.opt_prefix).plist_installed?
  rescue NotAKegError
    false
  end

  # Returns `true` if the service is loaded, else false.
  def loaded?
    # TODO: find replacement for deprecated "list"
    `#{ServicesCli.launchctl} list | grep #{label} 2>/dev/null`.chomp =~ /#{label}\z/
  end

  # Returns `true` if service is started (.plist is present in LaunchDaemon or LaunchAgent path), else `false`
  # Accepts Hash option `:as` with values `:root` for LaunchDaemon path or `:user` for LaunchAgent path.
  def started?(opts = { as: false })
    if opts[:as] && opts[:as] == :root
      (ServicesCli.boot_path + "#{label}.plist").exist?
    elsif opts[:as] && opts[:as] == :user
      (ServicesCli.user_path + "#{label}.plist").exist?
    else
      started?(as: :root) || started?(as: :user)
    end
  end

  def started_as
    return "root" if started?(as: :root)
    return ENV["HOME"].sub("/Users/", "") if started?(as: :user)
    nil
  end

  def error?
    !exit_code || exit_code.nonzero?
  end

  def unknown_status?
    !status || status.empty? || !pid || pid.zero?
  end

  # Get current PID of daemon process from launchctl.
  def pid
    return Regexp.last_match(1).to_i if status =~ status_regexp
  end

  def exit_code
    return Regexp.last_match(2).to_i if status =~ status_regexp
  end

  # Generate that plist file, dude.
  def generate_plist(data = nil)
    data ||= plist.file? ? plist : formula.plist

    if data.respond_to?(:file?) && data.file?
      data = data.read
    elsif data.respond_to?(:keys) && data.key?(:url)
      require "open-uri"
      data = URI.parse(data).read
    elsif !data
      odie "Could not read the plist for `#{name}`!"
    end

    # Replace "template" variables and ensure label is always, always homebrew.mxcl.<formula>
    data = data.to_s.gsub(/\{\{([a-z][a-z0-9_]*)\}\}/i) do |_|
      formula.send(Regexp.last_match(1)).to_s if formula.respond_to?(Regexp.last_match(1))
    end.gsub(%r{(<key>Label</key>\s*<string>)[^<]*(</string>)}, '\1' + label + '\2')

    # Always remove the "UserName" as it doesn't work since 10.11.5
    if data =~ %r{<key>UserName</key>}
      data = data.gsub(%r{(<key>UserName</key>\s*<string>)[^<]*(</string>)}, "")
    end

    if ARGV.verbose?
      ohai "Generated plist for #{formula.name}:"
      puts "   " + data.gsub("\n", "\n   ")
      puts
    end

    data
  end

  private

  def status
    @status ||= `#{ServicesCli.launchctl} list | grep #{label} 2>/dev/null`.chomp
  end

  def status_regexp
    /\A([\d-]+)\s+([\d]+)\s+#{label}\z/
  end
end

# Start the CLI dispatch stuff.
#
ServicesCli.run!
