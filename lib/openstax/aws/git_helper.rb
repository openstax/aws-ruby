require 'git'
require 'open-uri'

module OpenStax::Aws
  module GitHelper

    def self.sha_for_branch_name(org_slash_repo:, branch:)
      ::Git.ls_remote("https://github.com/#{org_slash_repo}")["branches"][branch][:sha]
    end

    def self.file_content_at_sha(org_slash_repo:, sha:, path:, github_token:)
      if github_token.blank?
        location = "https://raw.githubusercontent.com/#{org_slash_repo}/#{sha}/#{path}"
      else
        location = "https://raw.githubusercontent.com/#{org_slash_repo}/#{sha}/#{path}?token=#{github_token}"
      file = open(location)
      file.read
    end

  end
end
