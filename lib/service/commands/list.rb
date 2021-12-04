# frozen_string_literal: true

require "service/formulae"

module Service
  module Commands
    module List
      module_function

      TRIGGERS = [nil, "list", "ls"].freeze

      def run
        formulae = Formulae.services_list
        if formulae.empty?
          opoo("No services available to control with `#{Service::ServicesCli.bin}`")
          return
        end
        print_table(formulae)
      end

      # Print the table in the CLI
      # @private
      def print_table(formulae)
        longest_name = [formulae.max_by { |formula| formula[:name].length }[:name].length, 4].max
        longest_user = [formulae.map { |formula| formula[:user].nil? ? 4 : formula[:user].length }.max, 4].max

        headers = "#{Tty.bold}%-#{longest_name}.#{longest_name}<name>s %-7.7<status>s " \
                  "%-#{longest_user}.#{longest_user}<user>s %<file>s#{Tty.reset}"
        puts format(headers, name: "Name", status: "Status", user: "User", file: "File")

        formulae.each do |formula|
          status = get_status_string(formula[:status])
          status += formula[:exit_code].to_s if formula[:status] == :error
          file   = formula[:file]&.to_s&.gsub ENV["HOME"], "~" if formula[:loaded]

          row = "%-#{longest_name}.#{longest_name}<name>s %<status>s " \
                "%-#{longest_user}.#{longest_user}<user>s %<file>s"
          puts format(row, name: formula[:name], status: status, user: formula[:user], file: file)
        end
      end

      # Get formula status output
      # @private
      def get_status_string(status)
        case status
        when :started, :scheduled then "#{Tty.green}#{status}#{Tty.reset}"
        when :stopped, :none then status.to_s
        when :error   then "#{Tty.red}error  #{Tty.reset}"
        when :unknown then "#{Tty.yellow}unknown#{Tty.reset}"
        end
      end
    end
  end
end
