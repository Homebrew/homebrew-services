# frozen_string_literal: true

require "spec_helper"

describe Service::Commands::List do
  describe "#TRIGGERS" do
    it "contains all restart triggers" do
      expect(described_class::TRIGGERS).to eq([nil, "list", "ls"])
    end
  end

  describe "#run" do
    it "fails with empty list" do
      expect(Service::Formulae).to receive(:services_list).and_return([])
      expect do
        described_class.run
      end.to output("No services available to control with `brew services`\n").to_stdout
    end

    it "succeeds with list" do
      out = "<BOLD>Name    Status  User File<RESET>\nservice <GREEN>started<RESET> user /dev/null\n"
      formula = OpenStruct.new(name: "service", user: "user", status: :started, file: +"/dev/null")
      expect(Service::Formulae).to receive(:services_list).and_return([formula])
      expect do
        described_class.run
      end.to output(out).to_stdout
    end
  end

  describe "#print_table" do
    it "prints all standard values" do
      formula = { name: "a", user: "u", file: Pathname.new("/tmp/file.file"), status: :stopped }
      expect do
        described_class.print_table([formula])
      end.to output("<BOLD>Name Status  User File<RESET>\na    stopped u    /tmp/file.file\n").to_stdout
    end

    it "prints without user or file data" do
      formula = { name: "a", user: nil, file: nil, status: :stopped }
      expect do
        described_class.print_table([formula])
      end.to output("<BOLD>Name Status  User File<RESET>\na    stopped      \n").to_stdout
    end

    it "prints shortened home directory" do
      ENV["HOME"] = "/tmp"
      formula = { name: "a", user: "u", file: Pathname.new("/tmp/file.file"), status: :stopped }
      expect do
        described_class.print_table([formula])
      end.to output("<BOLD>Name Status  User File<RESET>\na    stopped u    ~/file.file\n").to_stdout
    end
  end

  describe "#get_status_string" do
    it "returns started" do
      expect(described_class.get_status_string(:started)).to eq("<GREEN>started<RESET>")
    end

    it "returns stopped" do
      expect(described_class.get_status_string(:stopped)).to eq("stopped")
    end

    it "returns error" do
      expect(described_class.get_status_string(:error)).to eq("<RED>error  <RESET>")
    end

    it "returns unknown" do
      expect(described_class.get_status_string(:unknown)).to eq("<YELLOW>unknown<RESET>")
    end

    it "returns other" do
      expect(described_class.get_status_string(:other)).to eq(nil)
    end
  end
end
