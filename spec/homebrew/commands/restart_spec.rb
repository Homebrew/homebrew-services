# frozen_string_literal: true

require "spec_helper"

describe Service::Commands::Restart do
  describe "#TRIGGERS" do
    it "contains all restart triggers" do
      expect(described_class::TRIGGERS).to eq(%w[restart relaunch reload r])
    end
  end

  describe "#run" do
    it "fails with empty list" do
      expect do
        described_class.run([], nil, verbose: false)
      end.to raise_error UsageError, "Formula(e) missing, please provide a formula name or use --all"
    end

    it "starts if services are not loaded" do
      expect(Service::ServicesCli).to receive(:start).once
      expect(Service::ServicesCli).not_to receive(:service_restart)
      service = OpenStruct.new(loaded?: false)

      expect(described_class.run([service], nil, verbose: false)).to be_nil
    end

    it "restarts if services are loaded" do
      expect(Service::ServicesCli).not_to receive(:start)
      expect(Service::ServicesCli).to receive(:service_restart).once.and_return(true)
      allow(described_class).to receive(:ohai).with(an_instance_of(String)).once
      service = OpenStruct.new(name: "name", service_name: "service_name", loaded?: true)

      expect(described_class.run([service], nil, verbose: false)).to be_nil
    end
  end
end
