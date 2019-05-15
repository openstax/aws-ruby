module OpenStax::Aws
  class Ec2InstanceData

    def self.get(key)
      endpoint = "http://169.254.169.254/latest/#{key}"
      Net::HTTP.get(URI.parse(endpoint))
    end

    def self.instance_id
      get("meta-data/instance-id")
    end

    def self.region
      get("meta-data/placement/availability-zone")[0..-2]
    end

  end
end
