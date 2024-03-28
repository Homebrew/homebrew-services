# frozen_string_literal: true

module Service
  module System
    extend FileUtils

    module_function

    # Path to launchctl binary.
    def launchctl
      @launchctl ||= which("launchctl")
    end

    # Is this a launchctl system
    def launchctl?
      launchctl.present?
    end

    # Path to systemctl binary.
    def systemctl
      @systemctl ||= which("systemctl")
    end

    # Is this a systemd system
    def systemctl?
      systemctl.present?
    end

    # Command scope modifier
    def systemctl_scope
      root? ? "--system" : "--user"
    end

    # Arguments to run systemctl.
    def systemctl_args
      @systemctl_args ||= [systemctl, systemctl_scope]
    end

    # Woohoo, we are root dude!
    def root?
      Process.euid.zero?
    end

    # Current user running `[sudo] brew services`.
    def user
      @user ||= ENV["USER"].presence || Utils.safe_popen_read("/usr/bin/whoami").chomp
    end

    def user_of_process(pid)
      if pid.nil? || pid.zero?
        user
      else
        Utils.safe_popen_read("ps", "-o", "user", "-p", pid.to_s).lines.second&.chomp
      end
    end

    # Run at boot.
    def boot_path
      if launchctl?
        Pathname.new("/Library/LaunchDaemons")
      elsif systemctl?
        Pathname.new("/usr/lib/systemd/system")
      end
    end

    # Run at login.
    def user_path
      if launchctl?
        Pathname.new("#{Dir.home}/Library/LaunchAgents")
      elsif systemctl?
        Pathname.new("#{Dir.home}/.config/systemd/user")
      end
    end

    # If root, return `boot_path`, else return `user_path`.
    def path
      root? ? boot_path : user_path
    end

    def domain_target
      if root?
        "system"
      elsif (ssh_tty = ENV.fetch("HOMEBREW_SSH_TTY", nil).present? && File.stat("/dev/console").uid != Process.uid) ||
            (sudo_user = ENV.fetch("HOMEBREW_SUDO_USER", nil).present?) ||
            (Process.uid != Process.euid)
        if @output_warning.blank? && ENV.fetch("HOMEBREW_SERVICES_NO_DOMAIN_WARNING", nil).blank?
          if ssh_tty
            opoo "running over SSH without /dev/console ownership, using user/* instead of gui/* domain!"
          elsif sudo_user
            opoo "running through sudo, using user/* instead of gui/* domain!"
          else
            opoo "uid and euid do not match, using user/* instead of gui/* domain!"
          end
          unless Homebrew::EnvConfig.no_env_hints?
            puts "Hide this warning by setting HOMEBREW_SERVICES_NO_DOMAIN_WARNING."
            puts "Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`)."
          end
          @output_warning = true
        end
        "user/#{Process.euid}"
      else
        "gui/#{Process.uid}"
      end
    end
  end
end
