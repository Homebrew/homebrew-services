# frozen_string_literal: true

require "spec_helper"

describe Homebrew::ServicesCli do
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
      expect(services_cli.user_of_process(50)).to eq(ENV["USER"])
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
    it "returns the user path" do
      expect(services_cli.user_path.to_s).to eq("/Users/#{ENV["USER"]}/Library/LaunchAgents")
    end
  end

  describe "#path" do
    it "returns the current relevant path" do
      expect(services_cli.path.to_s).to eq("/Users/#{ENV["USER"]}/Library/LaunchAgents")
    end
  end

  describe "#running" do
    it "returns the currently running services" do
      expect(services_cli.running).to eq(["homebrew.mxcl.php"])
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
end
