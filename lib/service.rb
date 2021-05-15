# frozen_string_literal: true

# Wrapper for a formula to handle service-related stuff like parsing and
# generating the plist file.
module Homebrew
  class Service
    # Access the `Formula` instance.
    attr_reader :formula

    # Create a new `Service` instance from either a path or label.
    def self.from(path_or_label)
      return unless path_or_label =~ path_or_label_regex

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
      @plist ||= formula.plist_path
    end

    # Whether the plist should be launched at startup
    def plist_startup?
      formula.plist_startup.present?
    end

    # Path to destination plist directory. If run as root, it's `boot_path`, else `user_path`.
    def dest_dir
      ServicesCli.root? ? ServicesCli.boot_path : ServicesCli.user_path
    end

    # Path to destination plist. If run as root, it's in `boot_path`, else `user_path`.
    def dest
      dest_dir + plist.basename
    end

    # Returns `true` if any version of the formula is installed.
    def installed?
      formula.any_version_installed?
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
      quiet_system ServicesCli.launchctl, "list", label
    end

    # Returns `true` if service is started (.plist is present in LaunchDaemon or LaunchAgent path), else `false`
    # Accepts Hash option `:as` with values `:root` for LaunchDaemon path or `:user` for LaunchAgent path.
    def started?(opts = { as: false })
      if opts[:as] && opts[:as] == :root
        (ServicesCli.boot_path + plist.basename).exist?
      elsif opts[:as] && opts[:as] == :user
        (ServicesCli.user_path + plist.basename).exist?
      else
        started?(as: :root) || started?(as: :user)
      end
    end

    def started_as
      return "root" if started?(as: :root)
      return ENV["HOME"].sub("/Users/", "") if started?(as: :user)

      nil
    end

    def pid?
      pid.present? && !pid.zero?
    end

    def error?
      return false if pid?

      exit_code.blank? || exit_code.nonzero?
    end

    def unknown_status?
      status.blank? && !pid?
    end

    # Get current PID of daemon process from launchctl.
    def pid
      return Regexp.last_match(1).to_i if status =~ pid_regex
    end

    def exit_code
      return Regexp.last_match(1).to_i if status =~ exit_code_regex
    end

    # Generate that plist file, dude.
    def generate_plist(data = nil, args:)
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
      end.gsub(%r{(<key>Label</key>\s*<string>)[^<]*(</string>)}, "\\1#{label}\\2")

      # Always remove the "UserName" as it doesn't work since 10.11.5
      if %r{<key>UserName</key>}.match?(data)
        data = data.gsub(%r{(<key>UserName</key>\s*<string>)[^<]*(</string>)}, "")
      end

      if args.verbose?
        ohai "Generated plist for #{formula.name}:"
        puts "   #{data.gsub("\n", "\n   ")}"
        puts
      end

      data
    end

    private

    def status
      @status ||= Utils.safe_popen_read("#{ServicesCli.launchctl} list '#{label}'").chomp
    end

    def exit_code_regex
      /"LastExitStatus"\ =\ ([0-9]*);/
    end

    def pid_regex
      /"PID"\ =\ ([0-9]*);/
    end

    private_class_method def self.path_or_label_regex
      /homebrew(?>\.mxcl)?\.([\w+-.@]+)(\.plist|\.service)?\z/
    end
  end
end
