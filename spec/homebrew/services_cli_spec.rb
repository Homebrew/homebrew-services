# frozen_string_literal: true

require "spec_helper"

describe Homebrew::ServicesCli do
  subject(:services_cli) { described_class }

  describe "#run!" do
    let(:subcommand) { "invalid_command" }
    let(:formula) { nil }
    let(:custom_plist) { nil }

    before do
      allow(Homebrew).to receive(:args).and_return(OpenStruct.new(named: [subcommand, formula, custom_plist]))
    end

    it "prints help message on invalid command" do
      expect { services_cli.run! }.to raise_error(UsageError, "unknown subcommand: #{subcommand}")
    end
  end
end
