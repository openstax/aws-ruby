module VcrHelperMethods

  def filter_rails_secret(path_to_secret)
    secret_name = path_to_secret.join("_")

    secret_value = Rails.application.secrets
    path_to_secret.each do |key|
      secret_value = secret_value[key]
    end

    filter_value(value: secret_value, with: secret_name)
  end

  def filter_env_var(env_var_name)
    filter_value(value: ENV[env_var_name], with: env_var_name)
  end

  def filter_value(value:, with:)
    VCR.configure do |c|
      if value.present?
        c.filter_sensitive_data("#{with}") { value }

        # If the secret value is a URL, it may be used without its protocol
        if value.starts_with?("http")
          value_without_protocol = value.sub(/^https?\:\/\//,'')
          c.filter_sensitive_data("#{with}_without_protocol") { value_without_protocol }
        end

        # If the secret value is inside a URL, it will be URL encoded which means it
        # may be different from value.  Handle this.
        url_value = CGI::escape(value.to_s)
        if value != url_value
          c.filter_sensitive_data("#{with}_url") { url_value }
        end
      end
    end
  end

  def vcr_friendly_uuids(count:, namespace: '')
    uuids = count.times.map{ SecureRandom.uuid }
    VCR.configure do |config|
      uuids.each_with_index{|uuid,ii| config.define_cassette_placeholder("<UUID_#{namespace}_#{ii}>") { uuid }}
    end
    uuids
  end

  def vcr_recording?
    !VCR.current_cassette.nil? && VCR.current_cassette.recording?
  end

  def vcr_playing_back?
    !VCR.current_cassette.nil? && !vcr_recording?
  end

  def vcr_configured_to_playback?
    :none == VCR.current_cassette.try(:record_mode) ||
    :none == VCR.configuration.default_cassette_options[:record] ||
    :none == VCR_OPTS[:record]
  end

  def do_not_record_or_playback
    # Pass blocks of code to this that do not want to record and that we later
    # do not want to run during playback (things we need to do for the spec
    # to run the first time but that aren't important to have in the cassette)

    # This method may be called in a spec (in which case there would be a cassette)
    # or before, in which case there isn't and we'd want to figure out if we are about
    # to playback.
    return if vcr_playing_back? || vcr_configured_to_playback?

    begin
      ENV['VCR_IGNORE_REQUESTS_TEMPORARILY'] = 'true'
      yield
    ensure
      ENV.delete('VCR_IGNORE_REQUESTS_TEMPORARILY')
    end
  end

  # def vcr_record_mode
  #   VCR.current_cassette.try(:record_mode) ||
  #   VCR.configuration.default_cassette_options[:record]
  # end

  def switch_to_temporary_aws_credentials
    # In the VCR configs, we have calls that mask AWS credentials in recorded AWS HTTP
    # interactions.  Just in case that ever doesn't work, this function changes the
    # credentials that are used over to temporary credentials (via an AWS STS call).
    # The temporary credentials expire after 15 minutes.

    # We only need to switch once; after we switch the env vars are set
    return if 'true' == ENV['switched_to_temporary_credentials']

    # Don't record this (as that would defeat the purpose of switching out credentials)
    # and don't play it back (because there won't be any records to playback)

    do_not_record_or_playback do
      ENV['AWS_MY_ARN'] = Aws::IAM::CurrentUser.new(region: "us-east-1").arn
      filter_env_var('AWS_MY_ARN')

      sts_client = Aws::STS::Client.new(region: "us-east-1")
      resp = sts_client.get_session_token({duration_seconds: 3600})

      ENV['AWS_ACCESS_KEY_ID'] = resp.credentials.access_key_id
      ENV['AWS_SECRET_ACCESS_KEY'] = resp.credentials.secret_access_key
      ENV['AWS_SESSION_TOKEN'] = resp.credentials.session_token
      filter_env_var('AWS_ACCESS_KEY_ID')
      filter_env_var('AWS_SECRET_ACCESS_KEY')
      filter_env_var('AWS_SESSION_TOKEN')

      ENV['AWS_ACCOUNT_ID'] = sts_client.get_caller_identity({})[:account]
      filter_env_var('AWS_ACCOUNT_ID')

      ENV['switched_to_temporary_credentials'] = 'true'
    end
  end

end
