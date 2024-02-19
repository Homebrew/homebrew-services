# frozen_string_literal: true

module Service
  module Formulae
    module_function

    # All available services, with optional filters applied
    # @private
    def available_services(loaded: nil, skip_root: false)
      require "formula"

      formulae = Formula.installed
             .map { |formula| FormulaWrapper.new(formula) }
             .select { |formula| formula.service? || formula.plist? }
             .sort_by(&:name)

      if loaded != nil
        formulae = formulae.select { |formula| formula.loaded? == loaded }
      end
      if skip_root
        formulae = formulae.select { |formula| formula.owner != "root" }
      end

      return formulae
    end

    # List all available services with status, user, and path to the file.
    def services_list
      available_services.map(&:to_hash)
    end
  end
end
