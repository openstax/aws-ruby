require 'yaml'

module OpenStax::Aws
  class ParametersSpecification

    attr_reader :data

    def self.from_file_name(file_name:, format:, top_key: nil)
      file = File.open(file_name, "r")
      content = file.read
      file.close
      new(content: content, format: format, top_key: top_key)
    end

    def self.from_git(org_slash_repo:, sha:, path:, format:, top_key: nil)
      content = OpenStax::Aws::GitHelper.file_content_at_sha(
                  org_slash_repo: org_slash_repo,
                  sha: sha,
                  path: path
                )
      new(content: content, format: format, top_key: top_key)
    end

    def self.from_content(content:, format:, top_key: nil)
      new(content: content, format: format, top_key: top_key)
    end

    def initialize(content:, format:, top_key: nil)
      raise "#{format} is not yet handled" if :yml != format

      @data = YAML.load(content)
      @data = data[top_key.to_s] if top_key
    end

    def expanded_data
      flat_hash(@data).map{|k,v| [k.join('/'), v]}.to_h
    end

    protected

    # https://stackoverflow.com/a/23861946
    def flat_hash(h,f=[],g={})
      return g.update({ f=>h }) unless h.is_a? Hash
      h.each { |k,r| flat_hash(r,f+[k],g) }
      g
    end

  end
end
