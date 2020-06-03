require 'open3'

module OpenStax::Aws
  class Packer_1_4_1

    def initialize(absolute_file_path:, dry_run: true)
      @logger = OpenStax::Aws.configuration.logger
      @only = []
      @vars = {}
      @dry_run = dry_run
      @verbose = false
      @very_verbose = false
      @debug = false
      @absolute_file_path = absolute_file_path
    end

    def only(builders)
      @only = [builders].flatten
    end

    def var(key, value)
      @vars[key.to_s] = value.to_s
    end

    def verbose!
      @verbose = true
    end

    def very_verbose!
      @very_verbose = true
    end

    def debug!
      @debug = true
    end

    def command
      cmd = "packer build"

      cmd = "#{cmd} --only=#{@only.join(',')}" if !@only.empty?

      @vars.each do |key, value|
        cmd = "#{cmd} --var '#{key}=#{value}'"
      end

      cmd = "PACKER_LOG=1 #{cmd}" if @verbose || @very_verbose
      cmd = "#{cmd} --debug" if @debug

      cmd = "#{cmd} #{@absolute_file_path}"
    end

    def run
      @logger.info("**** DRY RUN ****") if @dry_run
      @logger.info("Running: #{command}")

      if !@dry_run
        @logger.info("Printing stderr for desired verbosity")

        Open3.popen2e(command) do |stdin, stdout_err, wait_thr|
          while line=stdout_err.gets do
            puts(line) if @very_verbose || line =~ / amazon-ebs\: /
          end
        end
      end
    end

    def to_s
      command.to_s
    end

  end
end
