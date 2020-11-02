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

      cmd = "#{cmd} #{@absolute_file_path}"
    end

    def run
      @logger.info("**** DRY RUN ****") if @dry_run
      @logger.info("Running: #{command}")

      if !@dry_run
        @logger.info("Printing stderr for desired verbosity")
        ami = ""

        Open3.popen2e(command) do |stdin, stdout_err, wait_thr|
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

            line = ''

            while char = stdout_err.getc do
              line << char
              print char

              next unless char == "\n"

              matchami = line.match(/AMI: (ami-[0-9\-a-z]*)/i)
              ami = matchami.captures[0] if matchami

              line = ''
            end
          ensure
            # Restore previous interrupt unless we did so already
            Signal.trap 'INT', previous_interrupt_handler unless previous_interrupt_handler.nil?
          end

          puts ami

          # Return Packer's exit status wrapped in a Process::Status object
          wait_thr.value
        end
      end
    end

    def to_s
      command.to_s
    end

  end
end
