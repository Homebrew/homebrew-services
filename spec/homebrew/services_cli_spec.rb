# frozen_string_literal: true

require "spec_helper"

describe Service::ServicesCli do
  subject(:services_cli) { described_class }

  describe "#bin" do
    it "outputs command name" do
      expect(services_cli.bin).to eq("brew services")
    end
  end

  describe "#launchctl" do
    it "outputs launchctl command location" do
      expect(services_cli.launchctl).to eq("/bin/launchctl")
    end
  end

  describe "#launchctl?" do
    it "outputs launchctl presence" do
      expect(services_cli.launchctl?).to eq(true)
    end
  end

  describe "#systemctl?" do
    it "outputs systemctl presence" do
      expect(services_cli.systemctl?).to eq(true)
    end
  end

  describe "#systemctl" do
    it "outputs systemctl command location" do
      expect(services_cli.systemctl).to eq("/bin/systemctl")
    end
  end

  describe "#root?" do
    it "checks if the command is ran as root" do
      expect(services_cli.root?).to eq(false)
    end
  end

  describe "#user" do
    it "returns the current username" do
      expect(services_cli.user).to eq(ENV["USER"])
    end
  end

  describe "#user_of_process" do
    it "returns the username for empty PID" do
      expect(services_cli.user_of_process(nil)).to eq(ENV["USER"])
    end

    it "returns the PID username" do
      allow(Utils).to receive(:safe_popen_read).and_return <<~EOS
        USER
        user
      EOS
      expect(services_cli.user_of_process(50)).to eq("user")
    end
  end

  describe "#domain_target" do
    it "returns the current domain target" do
      expect(services_cli.domain_target).to match(%r{gui/(\d+)})
    end
  end

  describe "#boot_path" do
    it "returns the boot path" do
      expect(services_cli.boot_path.to_s).to eq("/Library/LaunchDaemons")
    end
  end

  describe "#user_path" do
    it "macOS - returns the user path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:launchctl?).and_return(true)
      allow(described_class).to receive(:systemctl?).and_return(false)
      expect(services_cli.user_path.to_s).to eq("/tmp_home/Library/LaunchAgents")
    end

    it "systemD - returns the user path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:launchctl?).and_return(false)
      allow(described_class).to receive(:systemctl?).and_return(true)
      expect(services_cli.user_path.to_s).to eq("/tmp_home/.config/systemd/user")
    end
  end

  describe "#path" do
    it "macOS - user - returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:root?).and_return(false)
      allow(described_class).to receive(:launchctl?).and_return(true)
      allow(described_class).to receive(:systemctl?).and_return(false)
      expect(services_cli.path.to_s).to eq("/tmp_home/Library/LaunchAgents")
    end

    it "macOS - root- returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:root?).and_return(true)
      allow(described_class).to receive(:launchctl?).and_return(true)
      allow(described_class).to receive(:systemctl?).and_return(false)
      expect(services_cli.path.to_s).to eq("/Library/LaunchDaemons")
    end

    it "systemD - user - returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:root?).and_return(false)
      allow(described_class).to receive(:launchctl?).and_return(false)
      allow(described_class).to receive(:systemctl?).and_return(true)
      expect(services_cli.path.to_s).to eq("/tmp_home/.config/systemd/user")
    end

    it "systemD - root- returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:root?).and_return(true)
      allow(described_class).to receive(:launchctl?).and_return(false)
      allow(described_class).to receive(:systemctl?).and_return(true)
      expect(services_cli.path.to_s).to eq("/usr/lib/systemd/system")
    end
  end

  describe "#running" do
    it "macOS - returns the currently running services" do
      allow(described_class).to receive(:launchctl?).and_return(true)
      allow(described_class).to receive(:systemctl?).and_return(false)
      allow(Utils).to receive(:popen_read).and_return <<~EOS
        77513   50  homebrew.mxcl.php
      EOS
      expect(services_cli.running).to eq(["homebrew.mxcl.php"])
    end

    it "systemD - returns the currently running services" do
      allow(described_class).to receive(:launchctl?).and_return(false)
      allow(Utils).to receive(:popen_read).and_return <<~EOS
        homebrew.php.service     loaded active running Homebrew PHP service
        systemd-udevd.service    loaded active running Rule-based Manager for Device Events and Files
        udisks2.service          loaded active running Disk Manager
        user@1000.service        loaded active running User Manager for UID 1000
      EOS
      expect(services_cli.running).to eq(["homebrew.php.service"])
    end
  end

  describe "#check" do
    it "checks the input does not exist" do
      expect do
        services_cli.check(nil)
      end.to output("Formula(e) missing, please provide a formula name or use --all\n").to_stdout
    end

    it "checks the input exists" do
      expect do
        services_cli.check("hello")
      end.not_to output("Formula(e) missing, please provide a formula name or use --all\n").to_stdout
    end
  end

  describe "#service_get_operational_status" do
    it "checks unknown_status" do
      service = OpenStruct.new(
        pid?:            false,
        error?:          false,
        unknown_status?: true,
      )
      expect(services_cli.service_get_operational_status(service)).to eq(:unknown)
    end

    it "checks error" do
      service = OpenStruct.new(
        pid?:            false,
        error?:          true,
        unknown_status?: false,
      )
      expect(services_cli.service_get_operational_status(service)).to eq(:error)
    end

    it "checks error output" do
      service = OpenStruct.new(
        pid?:            false,
        error?:          true,
        unknown_status?: false,
        exit_code:       40,
      )
      expect do
        services_cli.service_get_operational_status(service)
      end.to output("40\n").to_stdout
    end

    it "checks started" do
      service = OpenStruct.new(
        pid?:            true,
        error?:          false,
        unknown_status?: false,
      )
      expect(services_cli.service_get_operational_status(service)).to eq(:started)
    end
  end
end
