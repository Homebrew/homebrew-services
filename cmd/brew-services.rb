#!/usr/bin/env ruby -w

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
# Integrates homebrew formulae with MacOS X' `launchctl` manager. Services
# can either be added to `/Library/LaunchDaemons` or `~/Library/LaunchAgents`.
# Basically items added to `/Library/LaunchDaemons` are started at boot,
# those in `~/Library/LaunchAgents` at login.
#
# When started with `sudo` it operates on `/Library/LaunchDaemons`, else
# in the user space.
#
# Basically on `start` the plist file is generated and written to a `Tempfile`,
# then copied to the launch path (existing plists are overwritten).
#
# ## OPTIONS
#
# To access everything quickly, some aliases have been added:
#
#  * `rm`:
#    Shortcut for `cleanup`, because that's basically whats being done.
#
#  * `ls`:
#    Because `list` is too much to type :)
#
#  * `reload', 'r':
#    Alias for `restart`, which gracefully restarts selected service.
#
#  * `load`, `s`:
#    Alias for `start`, guess what it does...
#
#  * `unload`, `term`, `t`:
#    Alias for `stop`, stops and unloads selected service.
#
# ## SYNTAX
#
# Several existing formulae (like mysql, nginx) already write custom plist
# files to the formulae prefix. Most of these implement `#startup_plist`
# which then in turn returns a neat-o plist file as string.
#
# `brew services` operates on `#startup_plist` as well and requires
# supporting formulae to implement it. This method should either string
# containing the generated XML file, or return a `Pathname` instance which
# points to a plist template, or a hash like:
#
#    { :url => "https://gist.github.com/raw/534777/63c4698872aaef11fe6e6c0c5514f35fd1b1687b/nginx.plist.xml" }
#
# Some simple template parsing is performed, all variables like `{{name}}` are
# replaced by basically doing:
# `formula.send('name').to_s if formula.respond_to?('name')`, a bit like
# mustache. So any variable in the `Formula` is available as template
# variable, like `{{var}}`, `{{bin}}` usw.
#
# ## EXAMPLES
#
# Install and start service mysql at boot:
#
#     $ brew install mysql
#     $ sudo brew services start mysql
#
# Stop service mysql (when launched at boot):
#
#     $ sudo brew services stop mysql
#
# Start memcached at login:
#
#     $ brew install memcached
#     $ brew services start memcached
#
# List all running services for current user, and root:
#
#     $ brew services list
#     $ sudo brew services list
#
# Stop all running services for current user:
#
#     $ brew services stop --all
#
# ## BUGS
#
# `brew-services.rb` might not handle all edge cases, though it tries
# to fix problems by running `brew services cleanup`.
#
module ServicesCli
  class << self
    # Binary name.
    def bin; "brew services" end

    # Path to launchctl binary.
    def launchctl; which("launchctl") end

    # Wohoo, we are root dude!
    def root?; Process.uid == 0 end

    # Current user, i.e. owner of `HOMEBREW_CELLAR`.
    def user; @user ||= %x{/usr/bin/stat -f '%Su' #{HOMEBREW_CELLAR} 2>/dev/null}.chomp || %x{/usr/bin/whoami}.chomp end

    # Run at boot.
    def boot_path; Pathname.new("/Library/LaunchDaemons") end

    # Run at login.
    def user_path; Pathname.new(ENV['HOME'] + '/Library/LaunchAgents') end

    # If root returns `boot_path` else `user_path`.
    def path; root? ? boot_path : user_path end

    # Find all currently running services via launchctl list
    def running; %x{#{launchctl} list | grep homebrew.mxcl}.chomp.split("\n").map { |svc| $1 if svc =~ /(homebrew\.mxcl\..+)\z/ }.compact end

    # Check if running as homebrew and load required libraries et al.
    def homebrew!
      abort("Runtime error: homebrew is required, please start via `#{bin} ...`") unless defined?(HOMEBREW_LIBRARY_PATH)
      %w{fileutils pathname tempfile formula utils}.each { |req| require(req) }
      extend(FileUtils)
    end

    # All available services
    def available_services
      Formula.installed.map { |formula| Service.new(formula) }.select(&:plist?)
    end

    # Print usage and `exit(...)` with supplied exit code, if code
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
      usage if ARGV.empty? || ARGV.include?('help') || ARGV.include?('--help') || ARGV.include?('-h')

      # parse arguments
      act_on_all_services = !!ARGV.delete('--all')
      args = ARGV.reject { |arg| arg[0] == 45 }.map { |arg| arg.include?("/") ? arg : arg.downcase } # 45.chr == '-'
      cmd = args.shift
      formula = args.shift

      target = if act_on_all_services
        available_services
      elsif formula
        Service.new(Formula.factory(formula))
      end

      # dispatch commands and aliases
      case cmd
      when 'cleanup', 'clean', 'cl', 'rm' then cleanup
      when 'list', 'ls' then list
      when 'restart', 'relaunch', 'reload', 'r' then check(target) and restart(target)
      when 'start', 'launch', 'load', 's', 'l' then check(target) and start(target, args.first)
      when 'stop', 'unload', 'terminate', 'term', 't', 'u' then check(target) and stop(target)
      else
        onoe "Unknown command `#{cmd}`"
        usage(1)
      end
    end

    # Check if formula has been found
    def check(target)
      odie("Formula(e) missing, please provide a formula name or use --all") unless target
      true
    end

    # List all available services with status, user, and path to plist file
    def list
      formulae = available_services.map do |service|
        formula = {
          :name => service.formula.name,
          :started => false,
          :user => nil,
          :plist => nil
        }

        if service.started?(as: :root)
          formula[:started] = true
          formula[:user] = "root"
          formula[:plist] = ServicesCli.boot_path + "#{service.label}.plist"
        elsif service.started?(as: :user)
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

      longest_name = [formulae.max_by{ |formula|  formula[:name].length }[:name].length, 4].max
      longest_user = [formulae.map{ |formula|  formula[:user].nil? ? 4 : formula[:user].length }.max, 4].max

      puts "#{Tty.white}%-#{longest_name}.#{longest_name}s %-7.7s %-#{longest_user}.#{longest_user}s %s#{Tty.reset}" % ["Name", "Status", "User", "Plist"]
      formulae.each do |formula|
        puts "%-#{longest_name}.#{longest_name}s %s %-#{longest_user}.#{longest_user}s %s" % [formula[:name], formula[:started] ? "#{Tty.green}started#{Tty.reset}" : "stopped", formula[:user], formula[:plist]]
      end
    end

    # Kill services without plist file and remove unused plists
    def cleanup
      cleaned = []

      # 1. kill services which have no plist file
      running.each do |label|
        if svc = Service.from(label)
          if !svc.dest.file?
            puts "%-15.15s #{Tty.white}stale#{Tty.reset} => killing service..." % svc.name
            kill(svc)
            cleaned << label
          end
        else
          opoo "Service #{label} not managed by `#{bin}` => skipping"
        end
      end

      # 2. remove unused plist files
      Dir[path + 'homebrew.mxcl.*.plist'].each do |file|
        unless running.include?(File.basename(file).sub(/\.plist$/i, ''))
          puts "Removing unused plist #{file}"
          rm file
          cleaned << file
        end
      end

      puts "All #{root? ? 'root' : 'user-space'} services OK, nothing cleaned..." if cleaned.empty?
    end

    # Stop if loaded, then start again
    def restart(target)
      Array(target).each do |service|
        stop(service) if service.loaded?
        start(service)
      end
    end

    # Start a service
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
            odie "#{custom_plist} is not a url or exising file"
          end
        end

        odie "Formula `#{target.name}` not installed, #startup_plist not implemented or no plist file found" if !custom_plist && !target.plist?
      end

      Array(target).each do |service|
        temp = Tempfile.new(service.label)
        temp << service.generate_plist(custom_plist)
        temp.flush

        rm service.dest if service.dest.exist?
        service.dest_dir.mkpath unless service.dest_dir.directory?
        cp temp.path, service.dest

        # clear tempfile
        temp.close

        safe_system launchctl, "load", "-w", service.dest.to_s
        $?.to_i != 0 ? odie("Failed to start `#{service.name}`") : ohai("Successfully started `#{service.name}` (label: #{service.label})")
      end
    end

    # Stop a service or kill if no plist file available...
    def stop(target)
      if target.is_a?(Service) && !target.loaded?
        rm target.dest if target.dest.exist? # get rid of installed plist anyway, dude
        odie "Service `#{target.name}` not running, wanna start it? Try `#{bin} start #{target.name}`"
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

    # Kill service without plist file by issuing a `launchctl remove` command
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

# Wrapper for a formula to handle service related stuff like parsing
# and generating the plist file.
class Service
  # Access the `Formula` instance
  attr_reader :formula

  # Create a new `Service` instance from either a path or label.
  def self.from(path_or_label)
    return nil unless path_or_label =~ /homebrew\.mxcl\.([^\.]+)(\.plist)?\z/
    new(Formula.factory($1)) rescue nil
  end

  # Initialize new `Service` instance with supplied formula.
  def initialize(formula); @formula = formula end

  # Delegate access to `formula.name`.
  def name; @name ||= formula.name end

  # Label delegates to formula.plist_name, e.g `homebrew.mxcl.<formula>`.
  def label; @label ||= formula.plist_name end

  # Path to a static plist file, this is always `homebrew.mxcl.<formula>.plist`.
  def plist; @plist ||= formula.opt_prefix + "#{label}.plist" end

  # Path to destination plist directory, if run as root it's `boot_path`, else `user_path`.
  def dest_dir; (ServicesCli.root? ? ServicesCli.boot_path : ServicesCli.user_path) end

  # Path to destination plist, if run as root it's in `boot_path`, else `user_path`.
  def dest; dest_dir + "#{label}.plist" end

  # Returns `true` if any version of the formula is installed.
  def installed?; formula.installed? || ((dir = formula.opt_prefix).directory? && dir.children.length > 0) end

  # Returns `true` if formula implements #startup_plist or file exists.
  def plist?; installed? && (plist.file? || !formula.plist.nil? || !formula.startup_plist.nil?) end

  # Returns `true` if service is loaded, else false.
  def loaded?; %x{#{ServicesCli.launchctl} list | grep #{label} 2>/dev/null}.chomp =~ /#{label}\z/ end

  # Returns `true` if service is started (.plist is present in LaunchDaemon or LaunchAgent path), else `false`
  # Accepts Hash option `as:` with values `:root` for LaunchDaemon path or `:user` for LaunchAgent path.
  def started?(opts = {as: false})
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
    return ServicesCli.user if started?(as: :user)
    nil
  end

  # Get current PID of daemon process from launchctl.
  def pid
    status = %x{#{ServicesCli.launchctl} list | grep #{label} 2>/dev/null}.chomp
    return $1.to_i if status =~ /\A([\d]+)\s+.+#{label}\z/
  end

  # Generate that plist file, dude.
  def generate_plist(data = nil)
    data ||= plist.file? ? plist : formula.startup_plist

    if data.respond_to?(:file?) && data.file?
      data = data.read
    elsif data.respond_to?(:keys) && data.keys.include?(:url)
      require 'open-uri'
      data = open(data).read
    elsif !data
      odie "Could not read the plist for `#{name}`!"
    end

    # replace "template" variables and ensure label is always, always homebrew.mxcl.<formula>
    data = data.to_s.gsub(/\{\{([a-z][a-z0-9_]*)\}\}/i) { |m| formula.send($1).to_s if formula.respond_to?($1) }.
              gsub(%r{(<key>Label</key>\s*<string>)[^<]*(</string>)}, '\1' + label + '\2')

    # Force fix UserName
    if !ServicesCli.root?
      if data =~ %r{<key>UserName</key>}
        # Replace existing UserName value with current user
        data = data.gsub(%r{(<key>UserName</key>\s*<string>)[^<]*(</string>)}, '\1' + ServicesCli.user + '\2')
      else
        # Add UserName key and value to end of plist if it doesn't already exist
        data = data.gsub(%r{(\s*</dict>\s*</plist>)}, "\n    <key>UserName</key>\n    <string>" + ServicesCli.user + "</string>\\1")
      end
    elsif data =~ %r{<key>UserName</key>}
      # Always remove UserName key entirely if running as root
      data = data.gsub(%r{(<key>UserName</key>\s*<string>)[^<]*(</string>)}, '')
    end

    if ARGV.verbose?
      ohai "Generated plist for #{formula.name}:"
      puts "   " + data.gsub("\n", "\n   ")
      puts
    end

    data
  end
end

# Start the cli dispatch stuff.
#
ServicesCli.run!
