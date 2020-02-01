# frozen_string_literal: true

require "spec_helper"

describe Homebrew::Service do
  subject(:service) { described_class.new(formula) }

  let(:formula) do
    OpenStruct.new(
      opt_prefix: "/usr/local/opt/mysql/",
      plist_name: "mysql",
    )
  end

  describe "#plist" do
    it "outputs the full plist path" do
      expect(service.plist).to eq("/usr/local/opt/mysql/mysql.plist")
    end
  end
end
