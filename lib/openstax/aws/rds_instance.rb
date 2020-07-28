module OpenStax::Aws
  class RdsInstance

    attr_reader :raw

    delegate_missing_to :@raw

    def initialize(db_instance_identifier:, region:)
      @raw = Aws::RDS::DBInstance.new(
        db_instance_identifier,
        client: Aws::RDS::Client.new(region: region)
      )
    end

    def set_rds_master_password( db_instance_identifier: ,password:)
      raw.modify_rds_instance({
        db_instance_identifier: db_instance_identifier,
        apply_immediately: true, 
        master_user_password: password
      })
  
    end

  end
end

