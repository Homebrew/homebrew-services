# frozen_string_literal: true

module Service
  module ServicesCli
    extend FileUtils

    module_function

    # Binary name.
    def bin
      "brew services"
    end

    # Find all currently running services via launchctl list or systemctl list-units.
    def running
      if System.launchctl?
        # TODO: find replacement for deprecated "list"
        Utils.popen_read("#{System.launchctl} list | grep homebrew")
      else
        Utils.popen_read(System.systemctl, System.systemctl_scope, "list-units",
                         "--type=service",
                         "--state=running",
                         "--no-pager",
                         "--no-legend")
      end.chomp.split("\n").map do |svc|
        Regexp.last_match(1) if svc =~ /\s?(homebrew\.[a-z.]*)\s?/
      end.compact
    end

    # Check if formula has been found.
    def check(targets)
      raise UsageError, "Formula(e) missing, please provide a formula name or use --all" if targets.empty?

      true
    end

    # Kill services that don't have a service file
    def kill_orphaned_services
      cleaned = []
      running.each do |label|
        if (svc = FormulaWrapper.from(label))
          unless svc.dest.file?
            puts format("%-15.15<name>s #{Tty.bold}stale#{Tty.reset} => killing service...", name: svc.name)
            kill(svc)
            cleaned << label
          end
        else
          opoo "Service #{label} not managed by `#{bin}` => skipping"
        end
      end
      cleaned
    end

    def remove_unused_service_files
      cleaned = []
      Dir["#{System.path}homebrew.*.{plist,service}"].each do |file|
        next if running.include?(File.basename(file).sub(/\.(plist|service)$/i, ""))

        puts "Removing unused service file #{file}"
        rm file
        cleaned << file
      end

      cleaned
    end

    # Run a service as defined in the formula. This does not clean the service file like `start` does.
    def run(targets, verbose: false)
      targets.each do |service|
        if service.pid?
          puts "Service `#{service.name}` already running, use `#{bin} restart #{service.name}` to restart."
          next
        elsif System.root?
          puts "Service `#{service.name}` cannot be run (but can be started) as root."
          next
        end

        service_load(service, enable: false)
      end
    end

    # Start a service.
    def start(targets, service_file = nil, verbose: false)
      if service_file.present?
        file = Pathname.new service_file
        raise UsageError, "Provided service file does not exist" unless file.exist?
      end

      targets.each do |service|
        if service.pid?
          puts "Service `#{service.name}` already started, use `#{bin} restart #{service.name}` to restart."
          next
        end

        odie "Formula `#{service.name}` is not installed." unless service.installed?

        file ||= if service.service_file.exist? || System.systemctl? || service.formula.plist.blank?
          nil
        elsif service.formula.opt_prefix.exist? && (keg = Keg.for service.formula.opt_prefix) && keg.plist_installed?
          service_file = Dir["#{keg}/*#{service.service_file.extname}"].first
          Pathname.new service_file if service_file.present?
        end

        install_service_file(service, file)

        if file.blank? && verbose
          ohai "Generated plist for #{service.formula.name}:"
          puts "   #{service.dest.read.gsub("\n", "\n   ")}"
          puts
        end

        next if take_root_ownership(service).nil? && System.root?

        service_load(service, enable: true)
        @service_file = nil
      end
    end

    # Stop a service, or kill it if no service file is available.
    def stop(targets, verbose: false)
      targets.each do |service|
        unless service.loaded?
          rm service.dest if service.dest.exist? # get rid of installed service file anyway, dude
          if service.service_file_present?
            odie <<~EOS
              Service `#{service.name}` is started as `#{service.owner}`. Try:
                #{"sudo " unless System.root?}#{bin} stop #{service.name}
            EOS
          else
            opoo "Service `#{service.name}` is not started."
          end
          next
        end

        puts "Stopping `#{service.name}`... (might take a while)"
        if System.systemctl?
          quiet_system System.systemctl, System.systemctl_scope, "stop", service.service_name
          next
        end

        quiet_system System.launchctl, "bootout", "#{System.domain_target}/#{service.service_name}"
        while $CHILD_STATUS.to_i == 9216 || service.loaded?
          sleep(1)
          quiet_system System.launchctl, "bootout", "#{System.domain_target}/#{service.service_name}"
        end
        if service.dest.exist?
          ohai "Successfully stopped `#{service.name}` (label: #{service.service_name})"
        elsif service.loaded?
          kill(service)
        end
        rm service.dest if service.dest.exist?
      end
    end

    # Kill a service that has no plist file.
    def kill(service)
      quiet_system System.launchctl, "kill", "SIGTERM", "#{System.domain_target}/#{service.service_name}"
      while service.loaded?
        sleep(5)
        break if service.loaded?

        quiet_system System.launchctl, "kill", "SIGKILL", "#{System.domain_target}/#{service.service_name}"
      end
      ohai "Successfully stopped `#{service.name}` via #{service.service_name}"
    end

    # protections to avoid users editing root services
    def take_root_ownership(service)
      return unless System.root?

      chown "root", "admin", service.dest
      plist_data = service.dest.read
      plist = begin
        Plist.parse_xml(plist_data)
      rescue
        nil
      end
      return unless plist

      root_paths = []

      program_location = plist["ProgramArguments"]&.first
      key = "first ProgramArguments value"
      if program_location.blank?
        program_location = plist["Program"]
        key = "Program"
      end

      if program_location.present?
        Dir.chdir("/") do
          if File.exist?(program_location)
            program_location_path = Pathname(program_location).realpath
            root_paths += [
              program_location_path,
              program_location_path.parent.realpath,
            ]
          else
            opoo <<~EOS
              #{service.name}: the #{key} does not exist:
                #{program_location}
            EOS
          end
        end
      end
      if (formula = service.formula)
        root_paths += [
          formula.opt_prefix,
          formula.linked_keg,
          formula.bin,
          formula.sbin,
        ]
      end
      root_paths = root_paths.sort.uniq.select(&:exist?)

      opoo <<~EOS
        Taking root:admin ownership of some #{service.formula} paths:
          #{root_paths.join("\n  ")}
        This will require manual removal of these paths using `sudo rm` on
        brew upgrade/reinstall/uninstall.
      EOS
      chown "root", "admin", root_paths
      chmod "+t", root_paths
    end

    def launchctl_load(service, file:, enable:)
      safe_system System.launchctl, "enable", "#{System.domain_target}/#{service.service_name}" if enable
      safe_system System.launchctl, "bootstrap", System.domain_target, file
    end

    def systemd_load(service, enable:)
      safe_system System.systemctl, System.systemctl_scope, "start", service.service_name
      safe_system System.systemctl, System.systemctl_scope, "enable", service.service_name if enable
    end

    def service_load(service, enable:)
      if System.root? && !service.service_startup?
        opoo "#{service.name} must be run as non-root to start at user login!"
      elsif !System.root? && service.service_startup?
        opoo "#{service.name} must be run as root to start at system startup!"
      end

      if System.launchctl?
        file = enable ? service.dest : service.service_file
        launchctl_load(service, file: file, enable: enable)
      elsif System.systemctl?
        systemd_load(service, enable: enable)
      end

      function = enable ? "started" : "ran"
      ohai("Successfully #{function} `#{service.name}` (label: #{service.service_name})")
    end

    def install_service_file(service, file)
      odie "Formula `#{service.name}` is not installed" unless service.installed?

      unless service.service_file.exist?
        odie "Formula `#{service.name}` has not implemented #plist, #service or installed a locatable service file"
      end

      temp = Tempfile.new(service.service_name)
      temp << if file.blank?
        service.service_file.read
      else
        file.read
      end
      temp.flush

      rm service.dest if service.dest.exist?
      service.dest_dir.mkpath unless service.dest_dir.directory?
      cp temp.path, service.dest

      # Clear tempfile.
      temp.close

      chmod 0644, service.dest

      safe_system System.systemctl, System.systemctl_scope, "daemon-reload" if System.systemctl?
    end
  end
end
