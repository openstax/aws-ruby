module OpenStax
  module Aws
    class BuildImageCommand1

      # A standardized way to use Packer to build images.

      def initialize(ami_name_base:, region:,
                     verbose: false, very_verbose: false, debug: false,
                     github_org:, repo:, branch: nil, sha: nil,
                     packer_absolute_file_path: , playbook_absolute_file_path:,
                     dry_run: true)
        if sha.nil?
          branch ||= 'master'

          sha = OpenStax::Aws::GitHelper.sha_for_branch_name(
                  org_slash_repo: "#{github_org}/#{repo}",
                  branch: branch
                )
        end

        ami_name = "#{ami_name_base}@#{sha[0..6]} #{Time.now.utc.strftime("%y%m%d%H%MZ")}"

        @packer = OpenStax::Aws::PackerFactory.new_packer(
          absolute_file_path: packer_absolute_file_path,
          dry_run: dry_run
        )

        @packer.only("amazon-ebs")

        @packer.var("region", region)
        @packer.var("ami_name", ami_name)
        @packer.var("sha", sha)
        @packer.var("playbook_file", playbook_absolute_file_path)
        @packer.var("ami_description", {
          sha: sha,
          github_org: github_org,
          repo: repo
        }.to_json)

        @packer.verbose! if verbose
        @packer.very_verbose! if very_verbose
        @packer.debug! if debug
      end

      def run
        @packer.run
      end

      def to_s
        @packer.to_s
      end

    end
  end
end
