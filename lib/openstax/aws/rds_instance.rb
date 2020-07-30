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

    def set_master_password(password:)
      raw.modify({
        apply_immediately: true, 
        master_user_password: password
      })
  
    end

  end
end

