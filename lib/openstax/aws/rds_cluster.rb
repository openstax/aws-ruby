module OpenStax::Aws
  class RdsCluster

    attr_reader :raw

    delegate_missing_to :@raw

    def self.physical_resource_id_attribute
      :db_cluster_identifier
    end

    def initialize(db_cluster_identifier:, region:)
      @raw = Aws::RDS::DBCluster.new(
        db_cluster_identifier,
        client: Aws::RDS::Client.new(region: region)
      )
    end

    def set_master_password(password:)
      raw.modify({
        apply_immediately: true,
        master_user_password: password
      })
    end

  end
end
