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
      @label ||= if ServicesCli.launchctl?
        formula.plist_name
      elsif ServicesCli.systemctl?
        formula.service_name
      end
    end

    # Path to a static plist file. This is always `homebrew.mxcl.<formula>.plist`.
    def plist
      @plist ||= if ServicesCli.launchctl?
        formula.plist_path
      elsif ServicesCli.systemctl?
        formula.systemd_service_path
      end
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
      if ServicesCli.launchctl?
        # TODO: find replacement for deprecated "list"
        quiet_system ServicesCli.launchctl, "list", label
      elsif ServicesCli.systemctl?
        quiet_system ServicesCli.systemctl, ServicesCli.systemctl_scope, "list-unit-files", plist.basename
      end
    end

    # Returns `true` if service is present (.plist is present in LaunchDaemon or LaunchAgent path), else `false`
    # Accepts Hash option `:for` with values `:root` for LaunchDaemon path or `:user` for LaunchAgent path.
    def plist_present?(opts = { for: false })
      if opts[:for] && opts[:for] == :root
        boot_path_plist_present?
      elsif opts[:for] && opts[:for] == :user
        user_path_plist_present?
      else
        boot_path_plist_present? || user_path_plist_present?
      end
    end

    def owner
      return "root" if boot_path_plist_present?
      return ENV["USER"] if user_path_plist_present?

      nil
    end

    def pid?
      pid.present? && !pid.zero?
    end

    def error?
      return false if pid?

      exit_code.present? && exit_code.nonzero?
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
    def generate_plist(data = nil)
      data ||= plist.file? ? plist : formula.plist

      if data.respond_to?(:file?) && data.file?
        data = data.read
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

      data
    end

    private

    def status
      @status ||= if ServicesCli.launchctl?
        Utils.popen_read("#{ServicesCli.launchctl} list '#{label}'").chomp
      elsif ServicesCli.systemctl?
        Utils.popen_read(ServicesCli.systemctl.to_s, ServicesCli.systemctl_scope.to_s, "status", label.to_s).chomp
      end
    end

    def exit_code_regex
      if ServicesCli.launchctl?
        /"LastExitStatus"\ =\ ([0-9]*);/
      elsif ServicesCli.systemctl?
        /\(code=exited, status=([0-9]*)\)|\(dead\)/
      end
    end

    def pid_regex
      if ServicesCli.launchctl?
        /"PID"\ =\ ([0-9]*);/
      elsif ServicesCli.systemctl?
        /Main PID: ([0-9]*) \((?!code=)/
      end
    end

    def boot_path_plist_present?
      (ServicesCli.boot_path + plist.basename).exist?
    end

    def user_path_plist_present?
      (ServicesCli.user_path + plist.basename).exist?
    end

    private_class_method def self.path_or_label_regex
      /homebrew(?>\.mxcl)?\.([\w+-.@]+)(\.plist|\.service)?\z/
    end
  end
end
