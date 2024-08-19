# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  add_filter(/vendor|spec/)
  minimum_coverage 20
end

require "active_support/core_ext/string"

PROJECT_ROOT = Pathname(__dir__).parent.freeze
Dir.glob("#{PROJECT_ROOT}/lib/**/*.rb").each do |file|
  require file
end

SimpleCov.formatters = [SimpleCov::Formatter::HTMLFormatter]

require "sorbet-runtime"

require "bundler"
require "rspec/support/object_formatter"
require "stub/exceptions"

RSpec.configure do |config|
  config.filter_run_when_matching :focus
  config.expect_with :rspec do |c|
    c.max_formatted_output_length = 200
  end

  # Never truncate output objects.
  RSpec::Support::ObjectFormatter.default_instance.max_formatted_output_length = nil

  config.around do |example|
    Bundler.with_original_env { example.run }
  end
end

module Formatter
  def self.success(string, label: nil)
    string
  end

  def self.error(string, label: nil)
    string
  end
end

module Tty
  def self.green
    "<GREEN>"
  end

  def self.yellow
    "<YELLOW>"
  end

  def self.red
    "<RED>"
  end

  def self.default
    "<DEFAULT>"
  end

  def self.bold
    "<BOLD>"
  end

  def self.reset
    "<RESET>"
  end
end

module Homebrew
  module EnvConfig
    def self.no_emoji?
      false
    end
  end
end

module Utils
  def self.popen_read(*_cmd)
    ""
  end

  def self.safe_popen_read(*_args)
    ""
  end
end

module Service
  module System
    def self.which(cmd)
      "/bin/#{cmd}"
    end
  end

  module ServicesCli
    def self.safe_system(*_cmd)
      ""
    end

    def self.quiet_system(*_cmd)
      true
    end

    def self.odie(string)
      raise TestExit, string
    end

    def self.opoo(string)
      puts string
    end

    def self.ohai(string)
      puts string
    end
  end

  class FormulaWrapper
    def quiet_system(*_args)
      false
    end

    def odie(string)
      raise TestExit, string
    end

    def odebug(header, string); end
  end

  module Commands
    module List
      def self.opoo(string)
        puts string
      end
    end
  end
end

class Array
  def second
    self[1] if length >= 2
  end

  def verbose?; end
end
