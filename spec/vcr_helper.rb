require 'vcr'

include VcrHelperMethods

VCR.configure do |c|
  c.cassette_library_dir = 'spec/cassettes'
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.allow_http_connections_when_no_cassette = false
  c.ignore_localhost = false
  c.preserve_exact_body_bytes { |http_message| !http_message.body.valid_encoding? }
  # c.debug_logger = $stderr

  # Turn on debug logging, works in Travis too tho in full runs results
  # in Travis build logs that are too large and cause a Travis error
  # c.debug_logger = $stderr

  # We try to use temporary AWS credentials in specs (see TempAwsEnv), but just in
  # case we don't, we make sure to filter non-temp credentials that may be set
  # in the env vars when the spec run starts.

  filter_env_var('AWS_ACCESS_KEY_ID')
  filter_env_var('AWS_SECRET_ACCESS_KEY')
  filter_env_var('AWS_SESSION_TOKEN')

  # Probably not super critical to filter out the AWS Signature, because I believe the
  # signature includes header elements as well as the request body (so any change would
  # be found out), but for safety's sake we do it anyway.

  c.filter_sensitive_data('<SignatureValue>') do |interaction|
    (interaction.request.headers["Authorization"] || [""]).first.match(/Signature=([a-f0-9]+)/)
    $1
  end

  # This block lets us skip writing a few requests to a cassette.  Note those requests
  # must be skipped when a cassette isn't being recorded, otherwise VCR won't know what
  # to do with those requests.

  c.ignore_request do |request|
    'true' == ENV['VCR_IGNORE_REQUESTS_TEMPORARILY']
  end

end

VCR_OPTS = {
  # This should default to :none
  record: ENV['VCR_OPTS_RECORD'].try!(:to_sym) || :none,
  allow_unused_http_interactions: false
}

# VCR can update content length headers to solve various problems caused
# by recording and playing back requests and responses.  The update process
# happens in a before_playback hook.  Filtering senstive data also occurs
# in before hooks.  Since there isn't a way to make sure that the content
# length update happens after filtering senstive data (and since filtering
# data can mess with the content length), we end up not getting the benefit
# out of the update_content_length_header hook that we are shooting for.
# This monkey patch fixes this by forcing a content length update after
# every filtering of sensitive data.  This does more work than we need
# but it is also fast so it isn't that big of a deal.

class VCR::HTTPInteraction::HookAware
  alias_method :orig_filter!, :filter!

  def filter!(text, replacement_text)
    orig_filter!(text, replacement_text)
    response.update_content_length_header
  end
end
