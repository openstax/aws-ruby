module OpenStax::Aws
  module System

    def self.call(command, logger:, dry_run:)
      logger.info("**** DRY RUN ****") if dry_run
      logger.info("Running: #{command}")

      if !dry_run
        Open3.popen2e(command) do |stdin, stdout_err, wait_thr|
          while line=stdout_err.gets do
            STDERR.puts(line)
          end
        end
      end
    end

  end
end
