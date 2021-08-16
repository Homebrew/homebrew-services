# frozen_string_literal: true

require "spec_helper"

describe Service::FormulaWrapper do
  subject(:service) { described_class.new(formula) }

  let(:formula) do
    OpenStruct.new(
      opt_prefix:           "/usr/local/opt/mysql/",
      name:                 "mysql",
      plist_name:           "plist-mysql-test",
      service_name:         "plist-mysql-test",
      plist_path:           Pathname.new("/usr/local/opt/mysql/homebrew.mysql.plist"),
      systemd_service_path: Pathname.new("/usr/local/opt/mysql/homebrew.mysql.service"),
    )
  end

  describe "#service_file" do
    it "macOS - outputs the full service file path" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      expect(service.service_file.to_s).to eq("/usr/local/opt/mysql/homebrew.mysql.plist")
    end

    it "systemD - outputs the full service file path" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(false)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(true)
      expect(service.service_file.to_s).to eq("/usr/local/opt/mysql/homebrew.mysql.service")
    end
  end

  describe "#name" do
    it "outputs formula name" do
      expect(service.name).to eq("mysql")
    end
  end

  describe "#service_name" do
    it "macOS - outputs the service name" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      expect(service.service_name).to eq("plist-mysql-test")
    end

    it "systemD - outputs the service name" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(false)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(true)
      expect(service.service_name).to eq("plist-mysql-test")
    end
  end

  describe "#dest_dir" do
    it "macOS - user - outputs the destination directory for the service file" do
      ENV["HOME"] = "/tmp_home"
      allow(Service::ServicesCli).to receive(:root?).and_return(false)
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      expect(service.dest_dir.to_s).to eq("/tmp_home/Library/LaunchAgents")
    end

    it "macOS - root - outputs the destination directory for the service file" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      allow(Service::ServicesCli).to receive(:root?).and_return(true)
      expect(service.dest_dir.to_s).to eq("/Library/LaunchDaemons")
    end

    it "systemD - user - outputs the destination directory for the service file" do
      ENV["HOME"] = "/tmp_home"
      allow(Service::ServicesCli).to receive(:root?).and_return(false)
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(false)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(true)
      expect(service.dest_dir.to_s).to eq("/tmp_home/.config/systemd/user")
    end

    it "systemD - root - outputs the destination directory for the service file" do
      allow(Service::ServicesCli).to receive(:root?).and_return(true)
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(false)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(true)
      expect(service.dest_dir.to_s).to eq("/usr/lib/systemd/system")
    end
  end

  describe "#dest" do
    it "macOS - outputs the destination for the service file" do
      ENV["HOME"] = "/tmp_home"

      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(false)
      expect(service.dest.to_s).to eq("/tmp_home/Library/LaunchAgents/homebrew.mysql.plist")
    end

    it "systemD - outputs the destination for the service file" do
      ENV["HOME"] = "/tmp_home"

      allow(Service::ServicesCli).to receive(:launchctl?).and_return(false)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(true)
      expect(service.dest.to_s).to eq("/tmp_home/.config/systemd/user/homebrew.mysql.service")
    end
  end

  describe "#installed?" do
    it "outputs if the service formula is installed" do
      expect(service.installed?).to eq(nil)
    end
  end

  describe "#plist?" do
    it "outputs if the service is available" do
      expect(service.plist?).to eq(false)
    end
  end

  describe "#loaded?" do
    it "macOS - outputs if the service is loaded" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(false)
      allow(service).to receive(:quiet_system).and_return(false)
      expect(service.loaded?).to eq(false)
    end

    it "systemD - outputs if the service is loaded" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(false)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(true)
      allow(service).to receive(:quiet_system).and_return(false)
      expect(service.loaded?).to eq(false)
    end
  end

  describe "#service_file_present?" do
    it "macOS - outputs if the service file is present" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(false)
      expect(service.service_file_present?).to eq(false)
    end

    it "macOS - outputs if the service file is present for root" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(false)
      expect(service.service_file_present?(for: :root)).to eq(false)
    end

    it "macOS - outputs if the service file is present for user" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(false)
      expect(service.service_file_present?(for: :user)).to eq(false)
    end
  end

  describe "#owner?" do
    it "macOS - outputs the service file owner" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(false)
      expect(service.owner).to eq(nil)
    end
  end

  describe "#pid?" do
    it "outputs false because there is not pid" do
      allow(service).to receive(:pid).and_return(nil)
      expect(service.pid?).to eq(false)
    end
  end

  describe "#pid" do
    it "outputs nil because there is not pid" do
      expect(service.pid).to eq(nil)
    end
  end

  describe "#error?" do
    it "outputs false because there is no PID" do
      expect(service.error?).to eq(false)
    end
  end

  describe "#exit_code" do
    it "outputs nil because there is no exit code" do
      expect(service.exit_code).to eq(nil)
    end
  end

  describe "#unknown_status?" do
    it "outputs true because there is no PID" do
      expect(service.unknown_status?).to eq(true)
    end
  end

  describe "#service_startup?" do
    it "outputs false since there is no startup" do
      expect(service.service_startup?).to eq(false)
    end

    it "outputs true since there is a startup" do
      formula = OpenStruct.new(
        plist_startup: true,
      )

      service = described_class.new(formula)

      expect(service.service_startup?).to eq(true)
    end
  end

  describe "#generate_plist?" do
    it "macOS - outputs error for plist" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(false)
      expect do
        service.generate_plist(nil)
      end.to output("Could not read the plist for `mysql`!\n").to_stdout
    end
  end
end
