# frozen_string_literal: true

require "spec_helper"

describe Service::ServicesCli do
  subject(:services_cli) { described_class }

  describe "#bin" do
    it "outputs command name" do
      expect(services_cli.bin).to eq("brew services")
    end
  end

  describe "#running" do
    it "macOS - returns the currently running services" do
      allow(Service::System).to receive(:launchctl?).and_return(true)
      allow(Service::System).to receive(:systemctl?).and_return(false)
      allow(Utils).to receive(:popen_read).and_return <<~EOS
        77513   50  homebrew.mxcl.php
      EOS
      expect(services_cli.running).to eq(["homebrew.mxcl.php"])
    end

    it "systemD - returns the currently running services" do
      allow(Service::System).to receive(:launchctl?).and_return(false)
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
