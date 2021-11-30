# frozen_string_literal: true

require "spec_helper"

describe Service::Formulae do
  describe "#services_list" do
    it "empty list without available formulae" do
      allow(described_class).to receive(:available_services).and_return({})
      expect(described_class.services_list).to eq([])
    end

    it "LaunchD - represents root formula in list" do
      formula_stopped = instance_double(Service::FormulaWrapper)
      expect(formula_stopped).to receive(:name).and_return("formula")
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :root }).and_return(true)
      expect(formula_stopped).to receive(:pid?).and_return(true)
      expect(formula_stopped).to receive(:service_file).and_return(Pathname.new("file.plist"))
      expect(Service::System).to receive(:launchctl?).and_return(true)
      expect(Service::ServicesCli).to receive(:service_get_operational_status).and_return(:known)
      formulae = [
        formula_stopped,
      ]
      expected = [
        {
          file:   Pathname.new("/Library/LaunchDaemons/file.plist"),
          name:   "formula",
          status: :known,
          user:   "root",
        },
      ]
      allow(described_class).to receive(:available_services).and_return(formulae)
      expect(described_class.services_list).to eq(expected)
    end

    it "SystemD - represents root formula in list" do
      formula_stopped = instance_double(Service::FormulaWrapper)
      expect(formula_stopped).to receive(:name).and_return("formula")
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :root }).and_return(true)
      expect(formula_stopped).to receive(:pid?).and_return(true)
      expect(formula_stopped).to receive(:service_file).and_return(Pathname.new("file.service"))
      expect(Service::ServicesCli).to receive(:service_get_operational_status).and_return(:known)
      expect(Service::System).to receive(:launchctl?).and_return(false)
      expect(Service::System).to receive(:systemctl?).and_return(true)
      formulae = [
        formula_stopped,
      ]
      expected = [
        {
          file:   Pathname.new("/usr/lib/systemd/system/file.service"),
          name:   "formula",
          status: :known,
          user:   "root",
        },
      ]
      allow(described_class).to receive(:available_services).and_return(formulae)
      expect(described_class.services_list).to eq(expected)
    end

    it "LaunchD - represents user formula in list" do
      ENV["HOME"] = "/tmp_home"
      formula_stopped = instance_double(Service::FormulaWrapper)
      expect(formula_stopped).to receive(:name).and_return("formula")
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :root }).and_return(false)
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :user }).and_return(true)
      expect(formula_stopped).to receive(:pid?).and_return(true)
      expect(formula_stopped).to receive(:pid).and_return(10)
      expect(formula_stopped).to receive(:service_file).and_return(Pathname.new("file.plist"))
      expect(Service::System).to receive(:launchctl?).and_return(true)
      expect(Service::System).to receive(:user_of_process).with(10).and_return("user")
      expect(Service::ServicesCli).to receive(:service_get_operational_status).and_return(:known)
      formulae = [
        formula_stopped,
      ]
      expected = [
        {
          file:   Pathname.new("/tmp_home/Library/LaunchAgents/file.plist"),
          name:   "formula",
          status: :known,
          user:   "user",
        },
      ]
      allow(described_class).to receive(:available_services).and_return(formulae)
      expect(described_class.services_list).to eq(expected)
    end

    it "SystemD - represents user formula in list" do
      ENV["HOME"] = "/tmp_home"
      formula_stopped = instance_double(Service::FormulaWrapper)
      expect(formula_stopped).to receive(:name).and_return("formula")
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :root }).and_return(false)
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :user }).and_return(true)
      expect(formula_stopped).to receive(:pid?).and_return(true)
      expect(formula_stopped).to receive(:pid).and_return(10)
      expect(formula_stopped).to receive(:service_file).and_return(Pathname.new("file.service"))
      expect(Service::System).to receive(:launchctl?).and_return(false)
      expect(Service::System).to receive(:systemctl?).and_return(true)
      expect(Service::System).to receive(:user_of_process).with(10).and_return("user")
      expect(Service::ServicesCli).to receive(:service_get_operational_status).and_return(:known)
      formulae = [
        formula_stopped,
      ]
      expected = [
        {
          file:   Pathname.new("/tmp_home/.config/systemd/user/file.service"),
          name:   "formula",
          status: :known,
          user:   "user",
        },
      ]
      allow(described_class).to receive(:available_services).and_return(formulae)
      expect(described_class.services_list).to eq(expected)
    end

    it "LaunchD - represents loaded formula in list" do
      ENV["HOME"] = "/tmp_home"
      formula_stopped = instance_double(Service::FormulaWrapper)
      expect(formula_stopped).to receive(:name).and_return("formula")
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :root }).and_return(false)
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :user }).and_return(false)
      expect(formula_stopped).to receive(:loaded?).and_return(true)
      expect(formula_stopped).to receive(:service_file).and_return(Pathname.new("file.plist"))
      expect(Service::System).to receive(:user).and_return("user")
      expect(Service::ServicesCli).to receive(:service_get_operational_status).and_return(:known)
      formulae = [
        formula_stopped,
      ]
      expected = [
        {
          file:   Pathname.new("file.plist"),
          name:   "formula",
          status: :known,
          user:   "user",
        },
      ]
      allow(described_class).to receive(:available_services).and_return(formulae)
      expect(described_class.services_list).to eq(expected)
    end

    it "SystemD - represents loaded formula in list" do
      ENV["HOME"] = "/tmp_home"
      formula_stopped = instance_double(Service::FormulaWrapper)
      expect(formula_stopped).to receive(:name).and_return("formula")
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :root }).and_return(false)
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :user }).and_return(false)
      expect(formula_stopped).to receive(:loaded?).and_return(true)
      expect(formula_stopped).to receive(:service_file).and_return(Pathname.new("file.service"))
      expect(Service::System).to receive(:user).and_return("user")
      expect(Service::ServicesCli).to receive(:service_get_operational_status).and_return(:known)
      formulae = [
        formula_stopped,
      ]
      expected = [
        {
          file:   Pathname.new("file.service"),
          name:   "formula",
          status: :known,
          user:   "user",
        },
      ]
      allow(described_class).to receive(:available_services).and_return(formulae)
      expect(described_class.services_list).to eq(expected)
    end

    it "represents non-loaded formula in list" do
      ENV["HOME"] = "/tmp_home"
      formula_stopped = instance_double(Service::FormulaWrapper)
      expect(formula_stopped).to receive(:name).and_return("formula")
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :root }).and_return(false)
      expect(formula_stopped).to receive(:service_file_present?).with({ for: :user }).and_return(false)
      expect(formula_stopped).to receive(:loaded?).and_return(false)
      expect(Service::System).not_to receive(:launchctl?)
      expect(Service::System).not_to receive(:systemctl?)
      expect(Service::System).not_to receive(:user)
      expect(Service::ServicesCli).not_to receive(:service_get_operational_status)
      formulae = [
        formula_stopped,
      ]
      expected = [
        {
          file:   nil,
          name:   "formula",
          status: :stopped,
          user:   nil,
        },
      ]
      allow(described_class).to receive(:available_services).and_return(formulae)
      expect(described_class.services_list).to eq(expected)
    end
  end
end
