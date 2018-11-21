module OpenStax::Aws
  class BuildImageCommand

    def initialize(ami_name_base:, region:, branch: nil, sha: nil, verbose: false, debug: false, repo:,
                   packer_absolute_file_path: , playbook_absolute_file_path:)

      if sha.nil?
        branch ||= 'master'

        sha = OpenStax::Aws::GitHelper.sha_for_branch_name(
                org_slash_repo: "a15k/#{repo}",
                branch: branch
              )
      end

      ami_name = "#{ami_name_base}@#{sha[0..6]} #{Time.now.utc.strftime("%y%m%d%H%MZ")}"

      @cmd = "packer build --only=amazon-ebs"

      @cmd = "#{@cmd} --var 'region=#{region}'"
      @cmd = "#{@cmd} --var 'ami_name=#{ami_name}'"
      @cmd = "#{@cmd} --var 'sha=#{sha}'"
      @cmd = "#{@cmd} --var 'playbook_file=#{playbook_absolute_file_path}'"

      @cmd = "PACKER_LOG=1 #{@cmd}" if verbose
      @cmd = "#{@cmd} --debug" if debug

      @cmd = "#{@cmd} #{packer_absolute_file_path}"
    end

    def run
      `#{@cmd}`
    end

    def to_s
      @cmd
    end

  end
end
