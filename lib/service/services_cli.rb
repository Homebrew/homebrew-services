# typed: true
# frozen_string_literal: true

module Service
  module ServicesCli
    extend FileUtils

    def self.sudo_service_user
      @sudo_service_user
    end

    def self.sudo_service_user=(sudo_service_user)
      @sudo_service_user = sudo_service_user
    end

    # Binary name.
    def self.bin
      "brew services"
    end

    # Find all currently running services via launchctl list or systemctl list-units.
    def self.running
      if System.launchctl?
        Utils.popen_read(System.launchctl, "list")
      else
        Utils.popen_read(*System.systemctl_args, "list-units",
                         "--type=service",
                         "--state=running",
                         "--no-pager",
                         "--no-legend")
      end.chomp.split("\n").filter_map do |svc|
        Regexp.last_match(0) if svc =~ /homebrew(?>\.mxcl)?\.([\w+-.@]+)/
      end
    end

    # Check if formula has been found.
    def self.check(targets)
      raise UsageError, "Formula(e) missing, please provide a formula name or use --all" if targets.empty?

      true
    end

    # Kill services that don't have a service file
    def self.kill_orphaned_services
      cleaned_labels = []
      cleaned_services = []
      running.each do |label|
        if (service = FormulaWrapper.from(label))
          unless service.dest.file?
            cleaned_labels << label
            cleaned_services << service
          end
        else
          opoo "Service #{label} not managed by `#{bin}` => skipping"
        end
      end
      kill(cleaned_services)
      cleaned_labels
    end

    def self.remove_unused_service_files
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
    def self.run(targets, verbose: false)
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
    def self.start(targets, service_file = nil, verbose: false)
      file = T.let(nil, T.nilable(Pathname))

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

        file ||= if service.service_file.exist? || System.systemctl?
          nil
        elsif service.formula.opt_prefix.exist? && (keg = Keg.for service.formula.opt_prefix) && keg.plist_installed?
          service_file = Dir["#{keg}/*#{service.service_file.extname}"].first
          Pathname.new service_file if service_file.present?
        end

        install_service_file(service, file)

        if file.blank? && verbose
          ohai "Generated service file for #{service.formula.name}:"
          puts "   #{service.dest.read.gsub("\n", "\n   ")}"
          puts
        end

        next if take_root_ownership(service).nil? && System.root?

        service_load(service, enable: true)
      end
    end

    # Stop a service and unload it.
    def self.stop(targets, verbose: false, no_wait: false)
      targets.each do |service|
        unless service.loaded?
          rm service.dest if service.dest.exist? # get rid of installed service file anyway, dude
          if service.service_file_present?
            odie <<~EOS
              Service `#{service.name}` is started as `#{service.owner}`. Try:
                #{"sudo " unless System.root?}#{bin} stop #{service.name}
            EOS
          elsif System.launchctl? &&
                quiet_system(System.launchctl, "bootout", "#{System.domain_target}/#{service.service_name}")
            ohai "Successfully stopped `#{service.name}` (label: #{service.service_name})"
          else
            opoo "Service `#{service.name}` is not started."
          end
          next
        end

        systemctl_args = System.systemctl_args
        if no_wait
          systemctl_args << "--no-block"
          puts "Stopping `#{service.name}`..."
        else
          puts "Stopping `#{service.name}`... (might take a while)"
        end

        if System.systemctl?
          quiet_system(*systemctl_args, "disable", "--now", service.service_name)
        elsif System.launchctl?
          quiet_system System.launchctl, "bootout", "#{System.domain_target}/#{service.service_name}"
          unless no_wait
            while $CHILD_STATUS.to_i == 9216 || service.loaded?
              sleep(1)
              quiet_system System.launchctl, "bootout", "#{System.domain_target}/#{service.service_name}"
            end
          end
          quiet_system System.launchctl, "stop", "#{System.domain_target}/#{service.service_name}" if service.pid?
        end

        rm service.dest if service.dest.exist?
        # Run daemon-reload on systemctl to finish unloading stopped and deleted service.
        safe_system(*systemctl_args, "daemon-reload") if System.systemctl?

        if service.pid? || service.loaded?
          opoo "Unable to stop `#{service.name}` (label: #{service.service_name})"
        else
          ohai "Successfully stopped `#{service.name}` (label: #{service.service_name})"
        end
      end
    end

    # Stop a service but keep it registered.
    def self.kill(targets, verbose: false)
      targets.each do |service|
        if !service.pid?
          puts "Service `#{service.name}` is not started."
        elsif service.keep_alive?
          puts "Service `#{service.name}` is set to automatically restart and can't be killed."
        else
          puts "Killing `#{service.name}`... (might take a while)"
          if System.systemctl?
            quiet_system(*System.systemctl_args, "stop", service.service_name)
          elsif System.launchctl?
            quiet_system System.launchctl, "stop", "#{System.domain_target}/#{service.service_name}"
          end

          if service.pid?
            opoo "Unable to kill `#{service.name}` (label: #{service.service_name})"
          else
            ohai "Successfully killed `#{service.name}` (label: #{service.service_name})"
          end
        end
      end
    end

    # protections to avoid users editing root services
    def self.take_root_ownership(service)
      return unless System.root?
      return if sudo_service_user

      root_paths = T.let([], T::Array[Pathname])

      if System.systemctl?
        group = "root"
      elsif System.launchctl?
        group = "admin"
        chown "root", group, service.dest
        plist_data = service.dest.read
        plist = begin
          Plist.parse_xml(plist_data, marshal: false)
        rescue
          nil
        end
        return unless plist

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
        Taking root:#{group} ownership of some #{service.formula} paths:
          #{root_paths.join("\n  ")}
        This will require manual removal of these paths using `sudo rm` on
        brew upgrade/reinstall/uninstall.
      EOS
      chown "root", group, root_paths
      chmod "+t", root_paths
    end

    def self.launchctl_load(service, file:, enable:)
      safe_system System.launchctl, "enable", "#{System.domain_target}/#{service.service_name}" if enable
      safe_system System.launchctl, "bootstrap", System.domain_target, file
    end

    def self.systemd_load(service, enable:)
      safe_system(*System.systemctl_args, "start", service.service_name)
      safe_system(*System.systemctl_args, "enable", service.service_name) if enable
    end

    def self.service_load(service, enable:)
      if System.root? && !service.service_startup?
        opoo "#{service.name} must be run as non-root to start at user login!"
      elsif !System.root? && service.service_startup?
        opoo "#{service.name} must be run as root to start at system startup!"
      end

      if System.launchctl?
        file = enable ? service.dest : service.service_file
        launchctl_load(service, file:, enable:)
      elsif System.systemctl?
        # Systemctl loads based upon location so only install service
        # file when it is not installed. Used with the `run` command.
        install_service_file(service, nil) unless service.dest.exist?
        systemd_load(service, enable:)
      end

      function = enable ? "started" : "ran"
      ohai("Successfully #{function} `#{service.name}` (label: #{service.service_name})")
    end

    def self.install_service_file(service, file)
      odie "Formula `#{service.name}` is not installed" unless service.installed?

      unless service.service_file.exist?
        odie "Formula `#{service.name}` has not implemented #plist, #service or installed a locatable service file"
      end

      temp = Tempfile.new(service.service_name)
      temp << if file.blank?
        contents = service.service_file.read

        if sudo_service_user && System.launchctl?
          # set the username in the new plist file
          ohai "Setting username in #{service.service_name} to #{System.user}"
          plist_data = Plist.parse_xml(contents, marshal: false)
          plist_data["UserName"] = sudo_service_user
          plist_data.to_plist
        else
          contents
        end
      else
        file.read
      end
      temp.flush

      rm service.dest if service.dest.exist?
      service.dest_dir.mkpath unless service.dest_dir.directory?
      cp T.must(temp.path), service.dest

      # Clear tempfile.
      temp.close

      chmod 0644, service.dest

      safe_system(*System.systemctl_args, "daemon-reload") if System.systemctl?
    end
  end
end
