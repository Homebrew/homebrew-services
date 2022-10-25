# frozen_string_literal: true

require "spec_helper"

describe Service::System do
  describe "#launchctl" do
    it "outputs launchctl command location" do
      expect(described_class.launchctl).to eq("/bin/launchctl")
    end
  end

  describe "#launchctl?" do
    it "outputs launchctl presence" do
      expect(described_class.launchctl?).to be(true)
    end
  end

  describe "#systemctl?" do
    it "outputs systemctl presence" do
      expect(described_class.systemctl?).to be(true)
    end
  end

  describe "#systemctl_scope" do
    it "outputs systemctl scope for user" do
      allow(described_class).to receive(:root?).and_return(false)
      expect(described_class.systemctl_scope).to eq("--user")
    end

    it "outputs systemctl scope for root" do
      allow(described_class).to receive(:root?).and_return(true)
      expect(described_class.systemctl_scope).to eq("--system")
    end
  end

  describe "#systemctl" do
    it "outputs systemctl command location" do
      expect(described_class.systemctl).to eq("/bin/systemctl")
    end
  end

  describe "#root?" do
    it "checks if the command is ran as root" do
      expect(described_class.root?).to be(false)
    end
  end

  describe "#user" do
    it "returns the current username" do
      expect(described_class.user).to eq(ENV.fetch("USER"))
    end
  end

  describe "#user_of_process" do
    it "returns the username for empty PID" do
      expect(described_class.user_of_process(nil)).to eq(ENV.fetch("USER"))
    end

    it "returns the PID username" do
      allow(Utils).to receive(:safe_popen_read).and_return <<~EOS
        USER
        user
      EOS
      expect(described_class.user_of_process(50)).to eq("user")
    end

    it "returns nil if unavailable" do
      allow(Utils).to receive(:safe_popen_read).and_return <<~EOS
        USER
      EOS
      expect(described_class.user_of_process(50)).to be_nil
    end
  end

  describe "#domain_target" do
    let(:service) do
      OpenStruct.new(
        name:         "name",
        installed?:   true,
        service_file: OpenStruct.new(file?: Pathname.new("/tmp_home/Library/LaunchAgents/homebrew.mysql.plist")),
      )
    end

    it "returns the root domain target" do
      allow(described_class).to receive(:root?).and_return(true)
      expect(described_class.domain_target(service)).to match("system")
    end

    it "returns the current domain target for sessions with background support" do
      allow(described_class).to receive(:root?).and_return(false)
      allow(described_class).to receive(:domain_target_needs_background?).and_return(true)
      expect(described_class.domain_target(service)).to match(%r{user/(\d+)})
    end

    it "returns the current domain target" do
      allow(described_class).to receive(:root?).and_return(false)
      allow(described_class).to receive(:domain_target_needs_background?).and_return(false)
      expect(described_class.domain_target(service)).to match(%r{gui/(\d+)})
    end
  end

  describe "#boot_path" do
    it "macOS - returns the boot path" do
      allow(described_class).to receive(:launchctl?).and_return(true)
      expect(described_class.boot_path.to_s).to eq("/Library/LaunchDaemons")
    end

    it "SystemD - returns the boot path" do
      allow(described_class).to receive(:launchctl?).and_return(false)
      allow(described_class).to receive(:systemctl?).and_return(true)
      expect(described_class.boot_path.to_s).to eq("/usr/lib/systemd/system")
    end

    it "Unknown - returns no boot path" do
      allow(described_class).to receive(:launchctl?).and_return(false)
      allow(described_class).to receive(:systemctl?).and_return(false)
      expect(described_class.boot_path.to_s).to eq("")
    end
  end

  describe "#user_path" do
    it "macOS - returns the user path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:launchctl?).and_return(true)
      allow(described_class).to receive(:systemctl?).and_return(false)
      expect(described_class.user_path.to_s).to eq("/tmp_home/Library/LaunchAgents")
    end

    it "systemD - returns the user path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:launchctl?).and_return(false)
      allow(described_class).to receive(:systemctl?).and_return(true)
      expect(described_class.user_path.to_s).to eq("/tmp_home/.config/systemd/user")
    end

    it "Unknown - returns no user path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:launchctl?).and_return(false)
      allow(described_class).to receive(:systemctl?).and_return(false)
      expect(described_class.user_path.to_s).to eq("")
    end
  end

  describe "#path" do
    it "macOS - user - returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:root?).and_return(false)
      allow(described_class).to receive(:launchctl?).and_return(true)
      allow(described_class).to receive(:systemctl?).and_return(false)
      expect(described_class.path.to_s).to eq("/tmp_home/Library/LaunchAgents")
    end

    it "macOS - root- returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:root?).and_return(true)
      allow(described_class).to receive(:launchctl?).and_return(true)
      allow(described_class).to receive(:systemctl?).and_return(false)
      expect(described_class.path.to_s).to eq("/Library/LaunchDaemons")
    end

    it "systemD - user - returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:root?).and_return(false)
      allow(described_class).to receive(:launchctl?).and_return(false)
      allow(described_class).to receive(:systemctl?).and_return(true)
      expect(described_class.path.to_s).to eq("/tmp_home/.config/systemd/user")
    end

    it "systemD - root- returns the current relevant path" do
      ENV["HOME"] = "/tmp_home"
      allow(described_class).to receive(:root?).and_return(true)
      allow(described_class).to receive(:launchctl?).and_return(false)
      allow(described_class).to receive(:systemctl?).and_return(true)
      expect(described_class.path.to_s).to eq("/usr/lib/systemd/system")
    end
  end
end
