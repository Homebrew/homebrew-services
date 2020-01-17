# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/vendor/"
  minimum_coverage 20
end

PROJECT_ROOT ||= Pathname(__dir__).parent

Dir.glob("#{PROJECT_ROOT}/lib/**/*.rb").each do |file|
  require file
end

SimpleCov.formatters = [SimpleCov::Formatter::HTMLFormatter]

require "bundler"
require "rspec/support/object_formatter"

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
