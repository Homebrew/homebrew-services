# frozen_string_literal: true

require "spec_helper"
require "tempfile"

describe Service::FormulaWrapper do
  subject(:service) { described_class.new(formula) }

  let(:formula) do
    OpenStruct.new(
      opt_prefix:           "/usr/local/opt/mysql/",
      name:                 "mysql",
      plist_name:           "plist-mysql-test",
      service_name:         "plist-mysql-test",
      launchd_service_path: Pathname.new("/usr/local/opt/mysql/homebrew.mysql.plist"),
      systemd_service_path: Pathname.new("/usr/local/opt/mysql/homebrew.mysql.service"),
    )
  end

  describe "#service_file" do
    it "macOS - outputs the full service file path" do
      allow(Service::System).to receive(:launchctl?).and_return(true)
      expect(service.service_file.to_s).to eq("/usr/local/opt/mysql/homebrew.mysql.plist")
    end

    it "systemD - outputs the full service file path" do
      allow(Service::System).to receive(:launchctl?).and_return(false)
      allow(Service::System).to receive(:systemctl?).and_return(true)
      expect(service.service_file.to_s).to eq("/usr/local/opt/mysql/homebrew.mysql.service")
    end

    it "Other - outputs no service file" do
      allow(Service::System).to receive(:launchctl?).and_return(false)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      expect(service.service_file).to be_nil
    end
  end

  describe "#name" do
    it "outputs formula name" do
      expect(service.name).to eq("mysql")
    end
  end

  describe "#service_name" do
    it "macOS - outputs the service name" do
      allow(Service::System).to receive(:launchctl?).and_return(true)
      expect(service.service_name).to eq("plist-mysql-test")
    end

    it "systemD - outputs the service name" do
      allow(Service::System).to receive(:launchctl?).and_return(false)
      allow(Service::System).to receive(:systemctl?).and_return(true)
      expect(service.service_name).to eq("plist-mysql-test")
    end

    it "Other - outputs no service name" do
      allow(Service::System).to receive(:launchctl?).and_return(false)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      expect(service.service_name).to be_nil
    end
  end

  describe "#dest_dir" do
    it "macOS - user - outputs the destination directory for the service file" do
      ENV["HOME"] = "/tmp_home"
      allow(Service::System).to receive(:root?).and_return(false)
      allow(Service::System).to receive(:launchctl?).and_return(true)
      expect(service.dest_dir.to_s).to eq("/tmp_home/Library/LaunchAgents")
    end

    it "macOS - root - outputs the destination directory for the service file" do
      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:root?).and_return(true)
      expect(service.dest_dir.to_s).to eq("/Library/LaunchDaemons")
    end

    it "systemD - user - outputs the destination directory for the service file" do
      ENV["HOME"] = "/tmp_home"
      allow(Service::System).to receive(:root?).and_return(false)
      allow(Service::System).to receive(:launchctl?).and_return(false)
      allow(Service::System).to receive(:systemctl?).and_return(true)
      expect(service.dest_dir.to_s).to eq("/tmp_home/.config/systemd/user")
    end

    it "systemD - root - outputs the destination directory for the service file" do
      allow(Service::System).to receive(:root?).and_return(true)
      allow(Service::System).to receive(:launchctl?).and_return(false)
      allow(Service::System).to receive(:systemctl?).and_return(true)
      expect(service.dest_dir.to_s).to eq("/usr/lib/systemd/system")
    end
  end

  describe "#dest" do
    it "macOS - outputs the destination for the service file" do
      ENV["HOME"] = "/tmp_home"

      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      expect(service.dest.to_s).to eq("/tmp_home/Library/LaunchAgents/homebrew.mysql.plist")
    end

    it "systemD - outputs the destination for the service file" do
      ENV["HOME"] = "/tmp_home"

      allow(Service::System).to receive(:launchctl?).and_return(false)
      allow(Service::System).to receive(:systemctl?).and_return(true)
      expect(service.dest.to_s).to eq("/tmp_home/.config/systemd/user/homebrew.mysql.service")
    end
  end

  describe "#installed?" do
    it "outputs if the service formula is installed" do
      expect(service.installed?).to be_nil
    end
  end

  describe "#loaded?" do
    it "macOS - outputs if the service is loaded" do
      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      allow(service).to receive(:quiet_system).and_return(false)
      expect(service.loaded?).to be(false)
    end

    it "systemD - outputs if the service is loaded" do
      allow(Service::System).to receive(:launchctl?).and_return(false)
      allow(Service::System).to receive(:systemctl?).and_return(true)
      allow(service).to receive(:quiet_system).and_return(false)
      expect(service.loaded?).to be(false)
    end

    it "Other - outputs no status" do
      allow(Service::System).to receive(:launchctl?).and_return(false)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      expect(service.loaded?).to be_nil
    end
  end

  describe "#plist?" do
    it "false if not installed" do
      allow(service).to receive(:installed?).and_return(false)
      expect(service.plist?).to be(false)
    end

    it "true if installed and file" do
      tempfile = File.new("/tmp/foo", File::CREAT)
      allow(service).to receive(:installed?).and_return(true)
      allow(service).to receive(:service_file).and_return(Pathname.new(tempfile))
      expect(service.plist?).to be(true)
      File.delete(tempfile)
    end

    it "true if plist" do
      allow(service).to receive(:installed?).and_return(true)
      allow(service).to receive(:service_file).and_return(Pathname.new("/dev/null"))
      allow(service).to receive(:formula).and_return(OpenStruct.new(plist: "a"))
      expect(service.plist?).to be(true)
    end

    it "false if opt_prefix missing" do
      allow(service).to receive(:installed?).and_return(true)
      allow(service).to receive(:service_file).and_return(Pathname.new("/dev/null"))
      allow(service).to receive(:formula).and_return(OpenStruct.new(plist:      nil,
                                                                    opt_prefix: Pathname.new("/dfslkfhjdsolshlk")))
      expect(service.plist?).to be(false)
    end
  end

  describe "#owner" do
    it "root if file present" do
      allow(service).to receive(:boot_path_service_file_present?).and_return(true)
      expect(service.owner).to eq("root")
    end

    it "user if file present" do
      allow(service).to receive(:boot_path_service_file_present?).and_return(false)
      allow(service).to receive(:user_path_service_file_present?).and_return(true)
      allow(Service::System).to receive(:user).and_return("user")
      expect(service.owner).to eq("user")
    end

    it "nil if no file present" do
      allow(service).to receive(:boot_path_service_file_present?).and_return(false)
      allow(service).to receive(:user_path_service_file_present?).and_return(false)
      expect(service.owner).to be_nil
    end
  end

  describe "#service_file_present?" do
    it "macOS - outputs if the service file is present" do
      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      expect(service.service_file_present?).to be(false)
    end

    it "macOS - outputs if the service file is present for root" do
      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      expect(service.service_file_present?(for: :root)).to be(false)
    end

    it "macOS - outputs if the service file is present for user" do
      allow(Service::ServicesCli).to receive(:launchctl?).and_return(true)
      allow(Service::ServicesCli).to receive(:systemctl?).and_return(false)
      expect(service.service_file_present?(for: :user)).to be(false)
    end
  end

  describe "#owner?" do
    it "macOS - outputs the service file owner" do
      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      expect(service.owner).to be_nil
    end
  end

  describe "#pid?" do
    it "outputs false because there is not pid" do
      allow(service).to receive(:pid).and_return(nil)
      expect(service.pid?).to be(false)
    end
  end

  describe "#pid" do
    it "outputs nil because there is not pid" do
      expect(service.pid).to be_nil
    end
  end

  describe "#error?" do
    it "outputs false because there a no PID" do
      allow(service).to receive(:pid).and_return(nil)
      expect(service.error?).to be(false)
    end

    it "outputs false because there is a PID but no exit" do
      allow(service).to receive(:pid).and_return(12)
      allow(service).to receive(:exit_code).and_return(nil)
      expect(service.error?).to be(false)
    end
  end

  describe "#exit_code" do
    it "outputs nil because there is no exit code" do
      expect(service.exit_code).to be_nil
    end
  end

  describe "#unknown_status?" do
    it "outputs true because there is no PID" do
      expect(service.unknown_status?).to be(true)
    end
  end

  describe "#timed?" do
    it "returns true if timed service" do
      service_stub = OpenStruct.new(timed?: true)

      expect(service).to receive(:service?).once.and_return(true)
      expect(service).to receive(:load_service).once.and_return(service_stub)

      expect(service.timed?).to be(true)
    end

    it "returns false if no timed service" do
      service_stub = OpenStruct.new(timed?: false)

      expect(service).to receive(:service?).once.and_return(true)
      expect(service).to receive(:load_service).once.and_return(service_stub)

      expect(service.timed?).to be(false)
    end

    it "returns nil if no service" do
      expect(service).to receive(:service?).once.and_return(false)

      expect(service.timed?).to be_nil
    end
  end

  describe "#keep_alive?" do
    it "returns true if service needs to stay alive" do
      service_stub = OpenStruct.new(keep_alive?: true)

      expect(service).to receive(:service?).once.and_return(true)
      expect(service).to receive(:load_service).once.and_return(service_stub)

      expect(service.keep_alive?).to be(true)
    end

    it "returns false if service does not need to stay alive" do
      service_stub = OpenStruct.new(keep_alive?: false)

      expect(service).to receive(:service?).once.and_return(true)
      expect(service).to receive(:load_service).once.and_return(service_stub)

      expect(service.keep_alive?).to be(false)
    end

    it "returns nil if no service" do
      expect(service).to receive(:service?).once.and_return(false)

      expect(service.keep_alive?).to be_nil
    end
  end

  describe "#service_startup?" do
    it "outputs false since there is no startup" do
      expect(service.service_startup?).to be(false)
    end

    it "outputs true since there is a startup service" do
      service_stub = OpenStruct.new(requires_root?: true)

      expect(service).to receive(:service?).once.and_return(true)
      expect(service).to receive(:load_service).once.and_return(service_stub)

      expect(service.service_startup?).to be(true)
    end

    it "outputs true since there is a startup plist" do
      allow(described_class).to receive(:service?).and_return(false)
      formula = OpenStruct.new(
        plist_startup: true,
      )

      service = described_class.new(formula)

      expect(service.service_startup?).to be(true)
    end
  end

  describe "#generate_plist?" do
    it "macOS - outputs error for plist" do
      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      allow(described_class).to receive(:service_file_present?).and_return(false)
      allow(described_class).to receive(:service?).and_return(false)
      expect do
        service.generate_plist(nil)
      end.to raise_error TestExit, "Could not read the plist for `mysql`!"
    end
  end

  describe "#to_hash" do
    it "represents non-service values" do
      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      allow(described_class).to receive(:service?).and_return(false)
      allow(described_class).to receive(:service_file_present?).and_return(false)
      expected = {
        exit_code:    nil,
        file:         Pathname.new("/usr/local/opt/mysql/homebrew.mysql.plist"),
        loaded:       false,
        name:         "mysql",
        pid:          nil,
        running:      false,
        schedulable:  nil,
        service_name: "plist-mysql-test",
        status:       :none,
        user:         nil,
      }
      expect(service.to_hash).to eq(expected)
    end

    it "represents running non-service values" do
      ENV["HOME"] = "/tmp_home"
      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      expect(service).to receive(:service?).twice.and_return(false)
      expect(service).to receive(:service_file_present?).and_return(true)
      expected = {
        exit_code:    nil,
        file:         Pathname.new("/tmp_home/Library/LaunchAgents/homebrew.mysql.plist"),
        loaded:       false,
        name:         "mysql",
        pid:          nil,
        running:      false,
        schedulable:  nil,
        service_name: "plist-mysql-test",
        status:       :none,
        user:         nil,
      }
      expect(service.to_hash).to eq(expected)
    end

    it "represents service values" do
      ENV["HOME"] = "/tmp_home"
      service_stub = OpenStruct.new(command: "/bin/cmd", manual_command: "/bin/cmd")
      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      expect(service).to receive(:service?).twice.and_return(true)
      expect(service).to receive(:service_file_present?).and_return(true)
      expect(service).to receive(:load_service).twice.and_return(service_stub)
      expected = {
        command:        "/bin/cmd",
        cron:           nil,
        error_log_path: nil,
        exit_code:      nil,
        file:           Pathname.new("/tmp_home/Library/LaunchAgents/homebrew.mysql.plist"),
        interval:       nil,
        loaded:         false,
        log_path:       nil,
        name:           "mysql",
        pid:            nil,
        root_dir:       nil,
        running:        false,
        schedulable:    nil,
        service_name:   "plist-mysql-test",
        status:         :none,
        user:           nil,
        working_dir:    nil,
      }
      expect(service.to_hash).to eq(expected)
    end
  end
end
