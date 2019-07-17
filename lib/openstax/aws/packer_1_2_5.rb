module OpenStax::Aws
  class Packer_1_2_5

    def initialize(logger:, absolute_file_path:, dry_run: true)
      @logger = logger
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
      cmd = "packer build --only=amazon-ebs"

      cmd = "#{cmd} --only=#{@only.join(',')}" if !@only.empty?

      @vars.each do |key, value|
        cmd = "#{cmd} --var '#{key}=#{value}'"
      end

      cmd = "PACKER_LOG=1 #{cmd}" if @verbose || @very_verbose
      cmd = "#{cmd} --debug" if @debug

      cmd = "#{cmd} #{@absolute_file_path}"
    end

    def run
      @logger.info("**** DRY RUN ****") if dry_run
      @logger.info("Running: #{command}")

      if !dry_run
        if @verbose && !@very_verbose
          @logger.info("Printing stderr for desired verbosity")

          Open3.popen2e(command) do |stdin, stdout_err, wait_thr|
            while line=stdout_err.gets do
              puts(line) if line =~ / ui\: /
            end
          end
        else
          `#{@cmd}`
        end
      end
    end

  end
end
