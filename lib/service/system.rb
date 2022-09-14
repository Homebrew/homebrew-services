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

    # Woohoo, we are root dude!
    def root?
      Process.uid.zero?
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
      else
        "gui/#{Process.uid}"
      end
    end
  end
end
