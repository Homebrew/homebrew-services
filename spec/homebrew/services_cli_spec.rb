# frozen_string_literal: true

require "spec_helper"

describe Homebrew::ServicesCli do
  subject(:services_cli) { described_class }

  describe "#run!" do
    let(:cmd) { "invalid_command" }
    let(:formula) { nil }
    let(:custom_plist) { nil }

    before do
      allow(ARGV).to receive(:named).and_return([cmd, formula, custom_plist])
    end

    it "prints help message on invalid command" do
      expect(services_cli).to receive(:onoe).with("Unknown command `#{cmd}`!")
      expect(services_cli).to receive(:`).and_return("")
      expect { services_cli.run! }.to raise_error(SystemExit)
    end
  end
end
