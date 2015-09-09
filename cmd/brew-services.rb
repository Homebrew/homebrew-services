#!/usr/bin/env ruby -w

# brew-services(1) - Easily start and stop formulae via launchctl
# ===============================================================
#
# ## SYNOPSIS
#
# [<sudo>] `brew services` `list`<br>
# [<sudo>] `brew services` `restart` <formula><br>
# [<sudo>] `brew services` `start` <formula> [<plist>]<br>
# [<sudo>] `brew services` `stop` <formula><br>
# [<sudo>] `brew services` `cleanup`<br>
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

    # Print usage and `exit(...)` with supplied exit code, if code
    # is set to `false`, then exit is ignored.
    def usage(code = 0)
      puts "usage: [sudo] #{bin} [--help] <command> [<formula>]"
      puts
      puts "Small wrapper around `launchctl` for supported formulae, commands available:"
      puts "   cleanup Get rid of stale services and unused plists"
      puts "   list    List all services managed by `#{bin}`"
      puts "   restart Gracefully restart selected service"
      puts "   start   Start selected service"
      puts "   stop    Stop selected service"
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

    # Run and start the command loop.
    def run!
      homebrew!

      flags = ARGV.select { |arg| arg[0] == 45 }
      args = (ARGV - flags).map { |arg| arg.include?("/") ? arg : arg.downcase }
      ServicesCommand.execute(args, flags)
    end
  end
end

module ServicesCommand
  class << self
    def execute(args, flags)
      commands.each do |command_class|
        command = command_class.new(args, flags)
        if command.applicable?
          command.prepare
          command.execute
          break
        end
      end
    end

    def commands
      @commands ||= [Help, All, Start, Stop, Restart, List, Unknown]
    end
  end

  module Base
    attr_reader :args, :flags

    def initialize(args, flags)
      @args, @flags = args, flags
    end

    def prepare
    end
  end

  module Cli
    def cli
      ServicesCli
    end

    delegate :bin, :launchctl, :root?, :user, :boot_path, :user_path, :path, :running, :homebrew!, :usage, :kill, to: :cli
  end

  module Service
    attr_reader :service

    delegate :formula, :name, :label, :plist, :dest_dir, :dest, :installed?, :plist?, :loaded?, :pid, :generate_plist, to: :service

    def prepare
      super
      ensure_service!
    end

    def ensure_service!
      formula = args[1]
      odie("Formula missing, please provide a formula name") unless formula
      @service = Service.new(Formula.factory(@formula))
    end
  end

  class Help
    include Command::Base
    include Command::Cli

    def applicable?
      args.empty? || args.include?('help') || (flags & %w(-h --help)).any?
    end

    def execute
      usage
    end
  end

  class All
    include Command::Base

    def applicable?
      (flags & %w(-a --all)).any?
    end

    attr_reader :command, :other_args, :filtered_flags

    def prepare
      @other_args = args.dup
      @command = other_args.shift
      @filtered_flags = flags - %w(-a --all)
    end

    def execute
      formulae.each do |formula|
        ServicesCommand.execute([command, formula] + other_args, filtered_flags)
      end
    end

    private

    def formulae
      Formula.installed
        .map { |formula| Service.new(formula) }
        .select(&:plist?)
        .map { |service| service.formula.name }
    end
  end

  class Start
    include Command::Base
    include Command::Cli
    include Command::Service

    def applicable?
      (args & %w(start launch load s l)).any?
    end

    def prepare
      super
      ensure_not_started!
      ensure_plist!
    end

    def execute
      temp = Tempfile.new(label)
      temp << generate_plist(custom_plist)
      temp.flush

      rm dest if dest.exist?
      dest_dir.mkpath unless dest_dir.directory?
      cp temp.path, dest

      # clear tempfile
      temp.close

      safe_system launchctl, "load", "-w", dest.to_s
      $?.to_i != 0 ? odie("Failed to start `#{name}`") : ohai("Successfully started `#{name}` (label: #{label})")
    end

    private

    def ensure_not_started!
      return true unless loaded?
      odie "Service `#{name}` already started, use `#{bin} restart #{name}`"
    end

    def ensure_plist!
      return true if custom_plist || plist
      odie "Formula `#{name}` not installed, #startup_plist not implemented or no plist file found"
    end

    def custom_plist
      return @custom_plist if @custom_plist
      return unless custom_plist = args[2]
      return @custom_plist = { :url => custom_plist } if custom_plist =~ %r{\Ahttps?://.+}
      return @custom_plist = Pathname.new(custom_plist) if File.exist?(custom_plist)
      odie "#{custom_plist} is not a url or exising file"
    end
  end

  class Stop
    include Command::Base
    include Command::Cli
    include Command::Service

    def applicable?
      (args & %w(stop unload terminate term t u)).any?
    end

    def prepare
      super
      ensure_started!
    end

    def execute
      if dest.exist?
        puts "Stopping `#{name}`... (might take a while)"
        safe_system launchctl, "unload", "-w", dest.to_s
        $?.to_i != 0 ? odie("Failed to stop `#{name}`") : ohai("Successfully stopped `#{name}` (label: #{label})")
      else
        puts "Stopping stale service `#{name}`... (might take a while)"
        kill(service)
      end

      rm dest if dest.exist?
    end

    private

    def ensure_started!
      return true if loaded?
      rm dest if dest.exist? # get rid of installed plist anyway, dude
      odie "Service `#{name}` not running, wanna start it? Try `#{bin} start #{name}`"
    end
  end

  class Restart
    include Command::Base
    include Command::Service

    def applicable?
      (args & %w(restart relaunch reload r)).any?
    end

    def execute
      Stop.execute(args, flags) if loaded?
      Start.execute(args, flags)
    end
  end

  class List
    include Command::Base
    include Command::Cli

    def applicable?
      (args & %w(list ls)).any?
    end

    def execute
      formulae = Formula.installed
        .map { |formula|  Service.new(formula) }
        .select { |service|  service.plist?  }
        .map { |service|
          formula = {
            :name => service.formula.name,
            :status => false,
            :user => nil,
            :plist => nil
          };

          if (ServicesCli.boot_path + "#{service.label}.plist").exist?
            formula[:status] = true
            formula[:user] = "root"
            formula[:plist] = ServicesCli.boot_path + "#{service.label}.plist"
          elsif (ServicesCli.user_path + "#{service.label}.plist").exist?
            formula[:status] = true
            formula[:user] = ServicesCli.user
            formula[:plist] = ServicesCli.user_path + "#{service.label}.plist"
          end

          formula
        }

      opoo("No services available to control with `#{bin}`") and return if formulae.empty?

      longest_name = [formulae.max_by{ |formula|  formula[:name].length }[:name].length, 4].max
      longest_user = [formulae.map{ |formula|  formula[:user].nil? ? 4 : formula[:user].length }.max, 4].max

      puts "#{Tty.white}%-#{longest_name}.#{longest_name}s %-7.7s %-#{longest_user}.#{longest_user}s %s#{Tty.reset}" % ["Name", "Status", "User", "Plist"]
      formulae.each do |formula|
        puts "%-#{longest_name}.#{longest_name}s %s %-#{longest_user}.#{longest_user}s %s" % [formula[:name], formula[:status] ? "#{Tty.green}started#{Tty.reset}" : "stopped", formula[:user], formula[:plist]]
      end
    end
  end

  class Cleanup
    include Command::Base
    include Command::Cli

    def applicable?
      (args & %w(cleanup clean cl rm)).any?
      true
    end

    def execute
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
  end

  class Unknown
    include Command::Base
    include Command::Cli

    def applicable?
      true
    end

    def execute
      onoe "Unknown command `#{args[0]}`"
      usage(1)
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
