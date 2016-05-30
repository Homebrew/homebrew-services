# brew-services(1) - Easily start and stop formulae via launchctl
# ===============================================================
#
# ## SYNOPSIS
#
# [<sudo>] `brew services` `list`
# [<sudo>] `brew services` `restart` <formula>
# [<sudo>] `brew services` `start` <formula> [<plist>]
# [<sudo>] `brew services` `stop` <formula>
# [<sudo>] `brew services` `cleanup`
#
# ## DESCRIPTION
#
# Integrates Homebrew formulae with OS X's `launchctl` manager. Services can be
# added to either `/Library/LaunchDaemons` or `~/Library/LaunchAgents`.
# Basically, items in `/Library/LaunchDaemons` are started at boot, while those
# in `~/Library/LaunchAgents` are started at login.
#
# When started with `sudo`, it operates on `/Library/LaunchDaemons`; otherwise,
# it operates on `~/Library/LaunchAgents`.
#
# On `start` the plist file is generated and written to a `Tempfile`, and then
# copied to the launch path (existing plists are overwritten).
#
# ## OPTIONS
#
# To access everything quickly, some aliases have been added:
#
#  * `rm`:
#    Shortcut for `cleanup`, because that's basically what's being done.
#
#  * `ls`:
#    Because `list` is too much to type. :)
#
#  * `reload', 'r':
#    Alias for `restart`, which gracefully restarts the selected service.
#
#  * `load`, `s`:
#    Alias for `start`, guess what it does...
#
#  * `unload`, `term`, `t`:
#    Alias for `stop`, stops and unloads selected service.
#
# ## SYNTAX
#
# Several existing formulae (like mysql, nginx) already write a custom plist
# file to the formulae prefix. Most of these implement `#plist`, which
# then, in turn, returns a neato plist file as a string.
#
# `brew services` operates on `#plist` as well, and requires supporting
# formulae to implement it. This method should either return a string containing
# the generated XML file, or return a `Pathname` instance pointing to a plist
# template or to a hash like this:
#
#    { :url => "https://gist.github.com/raw/534777/63c4698872aaef11fe6e6c0c5514f35fd1b1687b/nginx.plist.xml" }
#
# Some simple template parsing is performed. All variables like `{{name}}` are
# replaced by basically doing the following:
# `formula.send('name').to_s if formula.respond_to?('name')`, a bit like
# mustache. So any variable in the `Formula` is available as a template
# variable, like `{{var}}`, `{{bin}}`, and `{{usr}}`.
#
# ## EXAMPLES
#
# Install and start the service "mysql" at boot:
#
#     $ brew install mysql
#     $ sudo brew services start mysql
#
# Stop the service "mysql" (after it was launched at boot):
#
#     $ sudo brew services stop mysql
#
# Start the service "memcached" at login:
#
#     $ brew install memcached
#     $ brew services start memcached
#
# List all running services for the current user and then for root:
#
#     $ brew services list
#     $ sudo brew services list
#
# Stop all running services for the current user:
#
#     $ brew services stop --all
#
# ## BUGS
#
# `brew-services.rb` might not handle all edge cases, but it will try to fix
# problems if you run `brew services cleanup`.
#
module ServicesCli
  class << self
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
      Process.uid == 0
    end

    # Current user, i.e., owner of `HOMEBREW_CELLAR`.
    def user
      @user ||= `/usr/bin/stat -f '%Su' #{HOMEBREW_CELLAR} 2>/dev/null`.chomp || `/usr/bin/whoami`.chomp
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
      `#{launchctl} list | grep homebrew.mxcl`.chomp.split("\n").map { |svc| $1 if svc =~ /(homebrew\.mxcl\..+)\z/ }.compact
    end

    # Check if running as Homebrew and load required libraries, et al.
    def homebrew!
      abort("Runtime error: Homebrew is required. Please start via `#{bin} ...`") unless defined?(HOMEBREW_LIBRARY_PATH)
      %w[fileutils pathname tempfile formula utils].each { |req| require(req) }
      extend(FileUtils)
    end

    # All available services
    def available_services
      Formula.installed.map { |formula| Service.new(formula) }.select(&:plist?)
    end

    # Print usage and `exit(...)` with supplied exit code. If code
    # is set to `false`, then exit is ignored.
    def usage(code = 0)
      puts "usage: [sudo] #{bin} [--help] <command> [<formula>|--all]"
      puts
      puts "Small wrapper around `launchctl` for supported formulae, commands available:"
      puts "   cleanup Get rid of stale services and unused plists"
      puts "   list    List all services managed by `#{bin}`"
      puts "   restart Gracefully restart service(s)"
      puts "   start   Start service(s)"
      puts "   stop    Stop service(s)"
      puts
      puts "Options, sudo and paths:"
      puts
      puts "  sudo   When run as root, operates on #{boot_path} (run at boot!)"
      puts "  Run at boot:  #{boot_path}"
      puts "  Run at login: #{user_path}"
      puts
      exit(code) unless code == false
      true
    end

    # Run and start the command loop.
    def run!
      homebrew!
      usage if ARGV.empty? || ARGV.include?("help") || ARGV.include?("--help") || ARGV.include?("-h")

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
        Service.new(Formula.factory(formula))
      end

      # Dispatch commands and aliases.
      case cmd
      when "cleanup", "clean", "cl", "rm" then cleanup
      when "list", "ls" then list
      when "restart", "relaunch", "reload", "r" then check(target) and restart(target)
      when "start", "launch", "load", "s", "l" then check(target) and start(target, custom_plist)
      when "stop", "unload", "terminate", "term", "t", "u" then check(target) and stop(target)
      else
        onoe "Unknown command `#{cmd}`"
        usage(1)
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
          :name => service.formula.name,
          :started => false,
          :user => nil,
          :plist => nil,
        }

        if service.started?(:as => :root)
          formula[:started] = true
          formula[:user] = "root"
          formula[:plist] = ServicesCli.boot_path + "#{service.label}.plist"
        elsif service.started?(:as => :user)
          formula[:started] = true
          formula[:user] = ServicesCli.user
          formula[:plist] = ServicesCli.user_path + "#{service.label}.plist"
        end

        formula
      end

      if formulae.empty?
        opoo("No services available to control with `#{bin}`")
        return
      end

      longest_name = [formulae.max_by { |formula| formula[:name].length }[:name].length, 4].max
      longest_user = [formulae.map { |formula| formula[:user].nil? ? 4 : formula[:user].length }.max, 4].max

      puts "#{Tty.white}%-#{longest_name}.#{longest_name}s %-7.7s %-#{longest_user}.#{longest_user}s %s#{Tty.reset}" % ["Name", "Status", "User", "Plist"]
      formulae.each do |formula|
        puts "%-#{longest_name}.#{longest_name}s %s %-#{longest_user}.#{longest_user}s %s" % [formula[:name], formula[:started] ? "#{Tty.green}started#{Tty.reset}" : "stopped", formula[:user], formula[:plist]]
      end
    end

    # Kill services that don't have a plist file, and remove unused plist files.
    def cleanup
      cleaned = []

      # 1. Kill services that don't have a plist file.
      running.each do |label|
        if svc = Service.from(label)
          unless svc.dest.file?
            puts "%-15.15s #{Tty.white}stale#{Tty.reset} => killing service..." % svc.name
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

    # Stop if loaded, then start again.
    def restart(target)
      Array(target).each do |service|
        stop(service) if service.loaded?
        start(service)
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
            custom_plist = { :url => custom_plist }
          elsif File.exist?(custom_plist)
            custom_plist = Pathname.new(custom_plist)
          else
            odie "#{custom_plist} is not a url or existing file"
          end
        elsif !target.plist.file? && target.formula.plist.nil?
          if target.formula.opt_prefix.exist? &&
             (keg = Keg.for target.formula.opt_prefix) &&
             keg.plist_installed?
            custom_plist = Pathname.new Dir["#{keg}/*.plist"].first
          else
            odie "Formula `#{target.name}` not installed, #plist not implemented or no plist file found"
          end
        end
      end

      Array(target).each do |service|
        temp = Tempfile.new(service.label)
        temp << service.generate_plist(custom_plist)
        temp.flush

        rm service.dest if service.dest.exist?
        service.dest_dir.mkpath unless service.dest_dir.directory?
        cp temp.path, service.dest

        # Clear tempfile.
        temp.close

        safe_system launchctl, "load", "-w", service.dest.to_s
        $?.to_i != 0 ? odie("Failed to start `#{service.name}`") : ohai("Successfully started `#{service.name}` (label: #{service.label})")
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
        if service.dest.exist?
          puts "Stopping `#{service.name}`... (might take a while)"
          safe_system launchctl, "unload", "-w", service.dest.to_s
          $?.to_i != 0 ? odie("Failed to stop `#{service.name}`") : ohai("Successfully stopped `#{service.name}` (label: #{service.label})")
        else
          puts "Stopping stale service `#{service.name}`... (might take a while)"
          kill(service)
        end
        rm service.dest if service.dest.exist?
      end
    end

    # Kill a service that has no plist file by issuing `launchctl remove`.
    def kill(svc)
      safe_system launchctl, "remove", svc.label
      odie("Failed to remove `#{svc.name}`, try again?") unless $?.to_i == 0
      while svc.loaded?
        puts "  ...checking status"
        sleep(5)
      end
      ohai "Successfully stopped `#{svc.name}` via #{svc.label}"
    end
  end
end

# Wrapper for a formula to handle service-related stuff like parsing and
# generating the plist file.
class Service
  # Access the `Formula` instance.
  attr_reader :formula

  # Create a new `Service` instance from either a path or label.
  def self.from(path_or_label)
    return nil unless path_or_label =~ /homebrew\.mxcl\.([^\.]+)(\.plist)?\z/
    begin
      new(Formula.factory($1))
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
  end

  # Returns `true` if the service is loaded, else false.
  def loaded?
    `#{ServicesCli.launchctl} list | grep #{label} 2>/dev/null`.chomp =~ /#{label}\z/
  end

  # Returns `true` if service is started (.plist is present in LaunchDaemon or LaunchAgent path), else `false`
  # Accepts Hash option `:as` with values `:root` for LaunchDaemon path or `:user` for LaunchAgent path.
  def started?(opts = {:as => false})
    if opts[:as] && opts[:as] == :root
      (ServicesCli.boot_path + "#{label}.plist").exist?
    elsif opts[:as] && opts[:as] == :user
      (ServicesCli.user_path + "#{label}.plist").exist?
    else
      started?(:as => :root) || started?(:as => :user)
    end
  end

  def started_as
    return "root" if started?(:as => :root)
    return ServicesCli.user if started?(:as => :user)
    nil
  end

  # Get current PID of daemon process from launchctl.
  def pid
    status = `#{ServicesCli.launchctl} list | grep #{label} 2>/dev/null`.chomp
    return $1.to_i if status =~ /\A([\d]+)\s+.+#{label}\z/
  end

  # Generate that plist file, dude.
  def generate_plist(data = nil)
    data ||= plist.file? ? plist : formula.plist

    if data.respond_to?(:file?) && data.file?
      data = data.read
    elsif data.respond_to?(:keys) && data.keys.include?(:url)
      require "open-uri"
      data = open(data).read
    elsif !data
      odie "Could not read the plist for `#{name}`!"
    end

    # Replace "template" variables and ensure label is always, always homebrew.mxcl.<formula>
    data = data.to_s.gsub(/\{\{([a-z][a-z0-9_]*)\}\}/i) { |_m| formula.send($1).to_s if formula.respond_to?($1) }.gsub(%r{(<key>Label</key>\s*<string>)[^<]*(</string>)}, '\1' + label + '\2')

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
end

# Start the CLI dispatch stuff.
#
ServicesCli.run!
