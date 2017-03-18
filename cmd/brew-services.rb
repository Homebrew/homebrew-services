# Start the CLI dispatch stuff.
if OS.linux?
  require_relative './systemd'
else
  require_relative './launchd'
end

ServicesCli.run!
