# frozen_string_literal: true

require "spec_helper"

describe Homebrew::ServicesCli do
  subject(:services_cli) { described_class }

  describe "#run!" do
    let(:subcommand) { "invalid_command" }
    let(:formula) { nil }
    let(:custom_plist) { nil }
    let(:args) { OpenStruct.new(named: [subcommand, formula, custom_plist]) }

    it "prints help message on invalid command" do
      expect { services_cli.run!(args) }.to raise_error(UsageError, "unknown subcommand: #{subcommand}")
    end
  end
end
