require 'open3'

module OpenStax::Aws
  class BuildImageCommand

    def initialize(ami_name_base:, region:, verbose: false, very_verbose: false, debug: false,
                   github_org: "openstax", repo:, branch: nil, sha: nil,
                   packer_absolute_file_path: , playbook_absolute_file_path:)

      @logger = OpenStax::Aws.configuration.logger
      @verbose = verbose
      @very_verbose = very_verbose

      if sha.nil?
        branch ||= 'master'

        sha = OpenStax::Aws::GitHelper.sha_for_branch_name(
                org_slash_repo: "#{github_org}/#{repo}",
                branch: branch
              )
      end

      ami_name = "#{ami_name_base}@#{sha[0..6]} #{Time.now.utc.strftime("%y%m%d%H%MZ")}"

      @cmd = "packer build --only=amazon-ebs"

      @cmd = "#{@cmd} --var 'region=#{region}'"
      @cmd = "#{@cmd} --var 'ami_name=#{ami_name}'"
      @cmd = "#{@cmd} --var 'sha=#{sha}'"
      @cmd = "#{@cmd} --var 'playbook_file=#{playbook_absolute_file_path}'"

      @cmd = "PACKER_LOG=1 #{@cmd}" if verbose || very_verbose
      @cmd = "#{@cmd} --debug" if debug

      @cmd = "#{@cmd} #{packer_absolute_file_path}"
    end

    def run(dry_run: true)
      @logger.info("**** DRY RUN ****") if dry_run
      @logger.info("Running: #{@cmd}")

      if !dry_run
        if @verbose && !@very_verbose
          @logger.info("Just printing stderr for desired verbosity")

          Open3.popen2e(@cmd) do |stdin, stdout_err, wait_thr|
            while line=stdout_err.gets do
              puts(line) if line =~ / ui\: /
            end
          end
        else
          `#{@cmd}`
        end
      end
    end

    def to_s
      @cmd
    end

  end
end
