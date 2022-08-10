# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  add_filter(/vendor|spec/)
  minimum_coverage 20
end

require "active_support/core_ext/string"

PROJECT_ROOT = Pathname(__dir__).parent.freeze
Dir.glob("#{PROJECT_ROOT}/lib/**/*.rb").sort.each do |file|
  require file
end

SimpleCov.formatters = [SimpleCov::Formatter::HTMLFormatter]

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
    Bundler.with_clean_env { example.run }
  end
end

module Formatter
  module_function

  def success(string)
    string
  end

  def error(string)
    string
  end
end

module Tty
  module_function

  def green
    "<GREEN>"
  end

  def yellow
    "<YELLOW>"
  end

  def red
    "<RED>"
  end

  def default
    "<DEFAULT>"
  end

  def bold
    "<BOLD>"
  end

  def reset
    "<RESET>"
  end
end

module Homebrew
  module EnvConfig
    module_function

    def no_emoji?
      false
    end
  end
end

module Utils
  module_function

  def popen_read(*_cmd)
    ""
  end

  def safe_popen_read(*_args)
    ""
  end
end

module Service
  module System
    module_function

    def which(cmd)
      "/bin/#{cmd}"
    end
  end

  module ServicesCli
    module_function

    def safe_system(*_cmd)
      ""
    end

    def quiet_system(*_cmd)
      true
    end

    def odie(string)
      raise TestExit, string
    end

    def opoo(string)
      puts string
    end

    def ohai(string)
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
  end

  module Commands
    module List
      module_function

      def opoo(string)
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
