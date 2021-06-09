# frozen_string_literal: true

require "spec_helper"

describe Homebrew::ServicesCli do
  subject(:services_cli) { described_class }

  describe "#check" do
    let(:formula) { nil }

    it "prints help message on invalid command" do
      expect do
        services_cli.check(formula)
      end.to output("Formula(e) missing, please provide a formula name or use --all\n").to_stdout
    end
  end
end
