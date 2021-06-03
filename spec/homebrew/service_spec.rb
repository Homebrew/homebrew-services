# frozen_string_literal: true

require "spec_helper"

describe Homebrew::Service do
  subject(:service) { described_class.new(formula) }

  let(:formula) do
    OpenStruct.new(
      opt_prefix: "/usr/local/opt/mysql/",
      name:       "mysql",
      plist_name: "plist-mysql-test",
      plist_path: Pathname.new("/usr/local/opt/mysql/homebrew.mysql.plist"),
    )
  end

  describe "#plist" do
    it "outputs the full plist path" do
      expect(service.plist.to_s).to eq("/usr/local/opt/mysql/homebrew.mysql.plist")
    end
  end

  describe "#name" do
    it "outputs formula name" do
      expect(service.name).to eq("mysql")
    end
  end

  describe "#label" do
    it "outputs the plist name" do
      expect(service.label).to eq("plist-mysql-test")
    end
  end

  describe "#dest_dir" do
    it "outputs the destination directory for the plist" do
      ENV["HOME"] = "/tmp_home"
      expect(service.dest_dir.to_s).to eq("/tmp_home/Library/LaunchAgents")
    end
  end

  describe "#dest" do
    it "outputs the destination for the plist" do
      ENV["HOME"] = "/tmp_home"
      expect(service.dest.to_s).to eq("/tmp_home/Library/LaunchAgents/homebrew.mysql.plist")
    end
  end

  describe "#installed?" do
    it "outputs if the plist formula is installed" do
      expect(service.installed?).to eq(nil)
    end
  end

  describe "#plist?" do
    it "outputs if the plist is available" do
      expect(service.plist?).to eq(false)
    end
  end

  describe "#loaded?" do
    it "outputs if the plist is loaded" do
      expect(service.loaded?).to eq(false)
    end
  end

  describe "#plist_present?" do
    it "outputs if the plist is present" do
      expect(service.plist_present?).to eq(false)
    end

    it "outputs if the plist is present for root" do
      expect(service.plist_present?(for: :root)).to eq(false)
    end

    it "outputs if the plist is present for user" do
      expect(service.plist_present?(for: :user)).to eq(false)
    end
  end

  describe "#owner?" do
    it "outputs the plist owner" do
      expect(service.owner).to eq(nil)
    end
  end

  describe "#pid?" do
    it "outputs false because there is not pid" do
      expect(service.pid?).to eq(false)
    end
  end

  describe "#pid" do
    it "outputs nil because there is not pid" do
      expect(service.pid).to eq(nil)
    end
  end

  describe "#error?" do
    it "outputs true because there is no PID" do
      expect(service.error?).to eq(true)
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

  describe "#plist_startup?" do
    it "outputs false since there is no startup" do
      expect(service.plist_startup?).to eq(false)
    end

    it "outputs true since there is a startup" do
      formula = OpenStruct.new(
        plist_startup: true,
      )

      service = described_class.new(formula)

      expect(service.plist_startup?).to eq(true)
    end
  end

  describe "#generate_plist?" do
    it "outputs error for plist" do
      expect do
        service.generate_plist(nil)
      end.to output("Could not read the plist for `mysql`!\n").to_stdout
    end
  end
end
