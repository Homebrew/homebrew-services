# frozen_string_literal: true

module Service
  module Formulae
    module_function

    # All available services
    # @private
    def available_services
      require "formula"

      Formula.installed
             .map { |formula| FormulaWrapper.new(formula) }
             .select(&:service?)
             .sort_by(&:name)
    end

    # List all available services with status, user, and path to the file.
    def services_list
      available_services.map(&:to_hash)
    end
  end
end
