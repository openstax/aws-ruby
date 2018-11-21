require 'git'
require 'open-uri'

module OpenStax::Aws
  module GitHelper

    def self.sha_for_branch_name(org_slash_repo:, branch:)
      ::Git.ls_remote("https://github.com/#{org_slash_repo}")["branches"][branch][:sha]
    end

    def self.file_content_at_sha(org_slash_repo:, sha:, path:)
      location = "https://raw.githubusercontent.com/#{org_slash_repo}/#{sha}/#{path}"
      file = open(location)
      file.read
    end

  end
end
