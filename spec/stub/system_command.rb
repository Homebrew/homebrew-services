# frozen_string_literal: true

class SystemCommand
  module Mixin
    def system_command(_cmd, *_args)
      Result.new
    end
  end

  class Result
    def stdout
      ""
    end

    def success?
      true
    end
  end
end
