require 'open3'

module OpenStax::Aws
  class Packer_1_4_1

    def initialize(absolute_file_path:, dry_run: true)
      @logger = OpenStax::Aws.configuration.logger
      @only = []
      @vars = {}
      @dry_run = dry_run
      @verbose = false
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

    def debug!
      @debug = true
    end

    def command
      cmd = "packer build"

      cmd = "#{cmd} --only=#{@only.join(',')}" if !@only.empty?

      @vars.each do |key, value|
        cmd = "#{cmd} --var '#{key}=#{value}'"
      end

      cmd = "PACKER_LOG=1 #{cmd}" if @verbose
      cmd = "#{cmd} --debug" if @debug

      cmd
    end

    def run
      @logger.info("**** DRY RUN ****") if @dry_run
      @logger.info("Running: #{command} #{@absolute_file_path}")

      if !@dry_run
        @logger.info("Printing stderr for desired verbosity")

        tmpdir = nil

        begin
          config_path = @absolute_file_path

          # Can't handle modifying HCL2 templates yet
          if config_path.ends_with?('.json')
            config = JSON.parse(File.read(config_path))
            config['post-processors'] ||= []
            manifest_config = (config['post-processors']).find do |processor|
              processor['type'] == 'manifest'
            end

            # Configure a manifest post-processor if not already configured
            if manifest_config.nil?
              tmpdir = Dir.mktmpdir

              manifest_config = { 'type' => 'manifest', 'output' => "#{tmpdir}/manifest.json" }

              config['post-processors'] << manifest_config

              config_path = "#{tmpdir}/packer.json"

              File.write(config_path, JSON.dump(config))
            end
          end

          Open3.popen2e("#{command} #{config_path}") do |stdin, stdout_err, wait_thr|
            begin
              previous_interrupt_handler = Signal.trap 'INT' do
                # Interrupt Packer
                Process.kill 'INT', wait_thr.pid

                # Restore previous interrupt handler so we don't interrupt Packer again
                Signal.trap 'INT', previous_interrupt_handler

                # Disable other code that restores previous interrupt
                previous_interrupt_handler = nil
              end

              stdout_err.sync = true

              # Send all packer output to STDERR
              while char = stdout_err.getc do
                STDERR.print char
              end
            ensure
              # Restore previous interrupt unless we did so already
              Signal.trap 'INT', previous_interrupt_handler unless previous_interrupt_handler.nil?
            end

            # Read the AMI ID from the manifest file and output it to STDOUT
            unless manifest_config.nil?
              manifest = File.read(manifest_config['output']) rescue nil

              puts JSON.parse(manifest)['builds'].last['artifact_id'].split(':', 2).last \
                unless manifest.nil?
            end

            # Return Packer's exit status wrapped in a Process::Status object
            wait_thr.value
          end
        ensure
          FileUtils.remove_entry(tmpdir) unless tmpdir.nil?
        end
      end
    end

    def to_s
      command.to_s
    end

  end
end
