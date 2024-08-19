# typed: true
# frozen_string_literal: true

require "service/formulae"

module Service
  module Commands
    module List
      TRIGGERS = [nil, "list", "ls"].freeze

      def self.run(json: false)
        formulae = Formulae.services_list
        if formulae.blank?
          opoo "No services available to control with `#{Service::ServicesCli.bin}`" if $stderr.tty?
          return
        end

        if json
          print_json(formulae)
        else
          print_table(formulae)
        end
      end

      JSON_FIELDS = [:name, :status, :user, :file, :exit_code].freeze

      # Print the JSON representation in the CLI
      # @private
      def self.print_json(formulae)
        services = formulae.map do |formula|
          formula.slice(*JSON_FIELDS)
        end

        puts JSON.pretty_generate(services)
      end

      # Print the table in the CLI
      # @private
      def self.print_table(formulae)
        services = formulae.map do |formula|
          status = get_status_string(formula[:status])
          status += formula[:exit_code].to_s if formula[:status] == :error
          file    = formula[:file].to_s.gsub(Dir.home, "~").presence if formula[:loaded]

          { name: formula[:name], status:, user: formula[:user], file: }
        end

        longest_name = [*services.map { |service| service[:name].length }, 4].max
        longest_status = [*services.map { |service| service[:status].length }, 15].max
        longest_user = [*services.map { |service| service[:user]&.length }, 4].compact.max

        # `longest_status` includes 9 color characters from `Tty.color` and `Tty.reset`.
        # We don't have these in the header row, so we don't need to add the extra padding.
        headers = "#{Tty.bold}%-#{longest_name}.#{longest_name}<name>s " \
                  "%-#{longest_status - 9}.#{longest_status - 9}<status>s " \
                  "%-#{longest_user}.#{longest_user}<user>s %<file>s#{Tty.reset}"
        row = "%-#{longest_name}.#{longest_name}<name>s " \
              "%-#{longest_status}.#{longest_status}<status>s " \
              "%-#{longest_user}.#{longest_user}<user>s %<file>s"

        puts format(headers, name: "Name", status: "Status", user: "User", file: "File")
        services.each do |service|
          puts format(row, **service)
        end
      end

      # Get formula status output
      # @private
      def self.get_status_string(status)
        case status
        when :started, :scheduled then "#{Tty.green}#{status}#{Tty.reset}"
        when :stopped, :none then "#{Tty.default}#{status}#{Tty.reset}"
        when :error   then "#{Tty.red}error  #{Tty.reset}"
        when :unknown then "#{Tty.yellow}unknown#{Tty.reset}"
        when :other then "#{Tty.yellow}other#{Tty.reset}"
        end
      end
    end
  end
end
