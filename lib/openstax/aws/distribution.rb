module OpenStax::Aws
  class Distribution

    attr_reader :id, :region, :logger

    def initialize(id:, region:, logger: nil)
      @id = id
      @region = region
      @logger ||= Logger.new(IO::NULL)
    end

    def invalidate(paths:, wait: false)
      paths = [paths].flatten.compact

      resp = client.create_invalidation({
        distribution_id: id,
        invalidation_batch: {
          paths: {
            quantity: paths.length,
            items: paths,
          },
          caller_reference: "#{paths.join(' ')} #{Time.now.utc.strftime("%Y%m%d-%H%M%S")}"
        },
      })

      invalidation_id = resp.invalidation.id

      logger.info("Created invalidation #{invalidation_id} for paths #{paths.join(', ')}.")

      wait_message = OpenStax::Aws::WaitMessage.new(
        message: "Waiting for invalidation #{invalidation_id} to be completed"
      )

      begin
        Aws::CloudFront::Waiters::InvalidationCompleted.new(
          client: client,
          before_attempt: ->(*) { wait_message.say_it }
        ).wait(
          distribution_id: id,
          id: invalidation_id
        )
      rescue Aws::Waiters::Errors::WaiterFailed => error
        logger.error "Waiting failed: #{error.message}"
        raise
      end
      logger.info "Invalidation #{invalidation_id} has been completed!"
    end

    protected

    def client
      @cloudfront_client ||= ::Aws::CloudFront::Client.new(region: region)
    end

  end
end
