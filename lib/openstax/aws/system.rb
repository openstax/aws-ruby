module OpenStax::Aws
  module System

    def self.call(command, logger: nil, dry_run:)
      logger&.info("**** DRY RUN ****") if dry_run
      logger&.info("Running: #{command}")

      if !dry_run
        Open3.popen2e(command) do |stdin, stdout_err, wait_thr|
          while line=stdout_err.gets do
            STDERR.puts(line)
          end

          exit_status = wait_thr.value.exitstatus
          exit(exit_status) if exit_status != 0
        end
      end
    end

  end
end
