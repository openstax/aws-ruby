require 'git'
require 'open-uri'
require 'byebug'

module OpenStax::Aws
  module GitHelper

    def self.sha_for_branch_name(org_slash_repo:, branch:)
      ::Git.ls_remote("https://github.com/#{org_slash_repo}")["branches"][branch][:sha]
    end

    def self.file_content_at_sha(org_slash_repo:, sha:, path:, github_token: nil )
      byebug
      if github_token.blank?
        location = "https://raw.githubusercontent.com/#{org_slash_repo}/#{sha}/#{path}"
        file = open(location)
        file.read
      else
        Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
          request = Net::HTTP::Get.new uri.request_uri
           request.basic_auth 'token', github_token
           response = http.request request
           response.body
        end
      end
    end
  end
end
