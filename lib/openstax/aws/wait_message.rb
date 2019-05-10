module OpenStax::Aws
  class WaitMessage

    def initialize(message:)
      @start_time = Time.now
      @message = message
    end

    def say_it
      elapsed_seconds = (Time.now - @start_time).round
      elapsed_minutes = elapsed_seconds / 60
      remainder_seconds = elapsed_seconds - (elapsed_minutes * 60)

      OpenStax::Aws.configuration.logger.debug(
        "#{@message}... (#{elapsed_minutes}m#{remainder_seconds}s elapsed)"
      )
    end

  end
end
