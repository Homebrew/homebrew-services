# frozen_string_literal: true

# Wrapper for a formula to handle service-related stuff like parsing and
# generating the service/plist files.
module Service
  class FormulaWrapper
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

    # Delegate access to `formula.service?`.
    def service?
      @service ||= @formula.service?
    end

    # Delegate access to `formula.service.timed?`.
    def timed?
      @timed ||= (load_service.timed? if service?)
    end

    # Delegate access to `formula.service.keep_alive?`.`
    def keep_alive?
      @keep_alive ||= (load_service.keep_alive? if service?)
    end

    # service_name delegates with formula.plist_name or formula.service_name for systemd (e.g., `homebrew.<formula>`).
    def service_name
      @service_name ||= if System.launchctl?
        formula.plist_name
      elsif System.systemctl?
        formula.service_name
      end
    end

    # service_file delegates with formula.plist_path or formula.systemd_service_path for systemd.
    def service_file
      @service_file ||= if System.launchctl?
        formula.plist_path
      elsif System.systemctl?
        formula.systemd_service_path
      end
    end

    # Whether the service should be launched at startup
    def service_startup?
      formula.plist_startup.present?
    end

    # Path to destination service directory. If run as root, it's `boot_path`, else `user_path`.
    def dest_dir
      System.root? ? System.boot_path : System.user_path
    end

    # Path to destination service. If run as root, it's in `boot_path`, else `user_path`.
    def dest
      dest_dir + service_file.basename
    end

    # Returns `true` if any version of the formula is installed.
    def installed?
      formula.any_version_installed?
    end

    # Returns `true` if the formula implements #plist or the plist file exists.
    def plist?
      return false unless installed?
      return true if service_file.file?
      return true unless formula.plist.nil?
      return false unless formula.opt_prefix.exist?
      return true if Keg.for(formula.opt_prefix).plist_installed?
    rescue NotAKegError
      false
    end

    # Returns `true` if the service is loaded, else false.
    def loaded?
      if System.launchctl?
        # TODO: find replacement for deprecated "list"
        quiet_system System.launchctl, "list", service_name
      elsif System.systemctl?
        quiet_system System.systemctl, System.systemctl_scope, "status", service_file.basename
      end
    end

    # Returns `true` if service is present (e.g. .plist is present in boot or user service path), else `false`
    # Accepts Hash option `:for` with values `:root` for boot path or `:user` for user path.
    def service_file_present?(opts = { for: false })
      if opts[:for] && opts[:for] == :root
        boot_path_service_file_present?
      elsif opts[:for] && opts[:for] == :user
        user_path_service_file_present?
      else
        boot_path_service_file_present? || user_path_service_file_present?
      end
    end

    def owner
      return "root" if boot_path_service_file_present?
      return System.user if user_path_service_file_present?

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

    # Get current PID of daemon process from status output.
    def pid
      return Regexp.last_match(1).to_i if status =~ pid_regex
    end

    # Get current exit code of daemon process from status output.
    def exit_code
      return Regexp.last_match(1).to_i if status =~ exit_code_regex
    end

    # Generate that plist file, dude.
    def generate_plist(data = nil)
      data ||= service_file.file? ? service_file : formula.plist

      if data.respond_to?(:file?) && data.file?
        data = data.read
      elsif !data
        odie "Could not read the plist for `#{name}`!"
      end

      # Replace "template" variables and ensure label is always, always #service_name
      data = data.to_s.gsub(/\{\{([a-z][a-z0-9_]*)\}\}/i) do |_|
        formula.send(Regexp.last_match(1)).to_s if formula.respond_to?(Regexp.last_match(1))
      end.gsub(%r{(<key>Label</key>\s*<string>)[^<]*(</string>)}, "\\1#{service_name}\\2")

      # Always remove the "UserName" as it doesn't work since 10.11.5
      if %r{<key>UserName</key>}.match?(data)
        data = data.gsub(%r{(<key>UserName</key>\s*<string>)[^<]*(</string>)}, "")
      end

      data
    end

    def to_hash
      hash = {
        name:         name,
        service_name: service_name,
        running:      pid?,
        loaded:       loaded?,
        schedulable:  timed?,
        pid:          pid,
        exit_code:    exit_code,
        user:         owner,
        status:       operational_status,
        file:         service_file_present? ? dest : service_file,
      }

      return hash unless service?

      service = load_service
      hash[:command] = service.manual_command
      hash[:working_dir] = service.working_dir
      hash[:root_dir] = service.root_dir
      hash[:log_path] = service.log_path
      hash[:error_log_path] = service.error_log_path
      hash[:interval] = service.interval
      hash[:cron] = service.cron

      hash
    end

    private

    # The purpose of this function is to lazy load the Homebrew::Service class
    # and avoid nameclashes with the current Service module.
    # It should be used instead of calling formula.service directly.
    def load_service
      require_relative "../../../../../Homebrew/service"

      formula.service
    end

    def operational_status
      if pid?
        :started
      elsif !loaded?
        :none
      elsif exit_code.present? && exit_code.zero?
        if timed?
          :scheduled
        else
          :stopped
        end
      elsif error?
        :error
      elsif unknown_status?
        :unknown
      else
        :other
      end
    end

    def status
      @status ||= if System.launchctl?
        Utils.popen_read(System.launchctl, "list", service_name).chomp
      elsif System.systemctl?
        Utils.popen_read(System.systemctl.to_s, System.systemctl_scope.to_s, "status",
                         service_name.to_s).chomp
      end
    end

    def exit_code_regex
      if System.launchctl?
        /"LastExitStatus"\ =\ ([0-9]*);/
      elsif System.systemctl?
        /\(code=exited, status=([0-9]*)\)|\(dead\)/
      end
    end

    def pid_regex
      if System.launchctl?
        /"PID"\ =\ ([0-9]*);/
      elsif System.systemctl?
        /Main PID: ([0-9]*) \((?!code=)/
      end
    end

    def boot_path_service_file_present?
      (System.boot_path + service_file.basename).exist?
    end

    def user_path_service_file_present?
      (System.user_path + service_file.basename).exist?
    end

    private_class_method def self.path_or_label_regex
      /homebrew(?>\.mxcl)?\.([\w+-.@]+)(\.plist|\.service)?\z/
    end
  end
end
