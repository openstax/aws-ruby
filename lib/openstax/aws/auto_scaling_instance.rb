module OpenStax::Aws
  class AutoScalingInstance

    attr_reader :raw

    delegate_missing_to :@raw

    def initialize(group_name:, id:, region:)
      @raw = Aws::AutoScaling::Instance.new(
        group_name,
        id,
        client: Aws::AutoScaling::Client.new(region: region)
      )
    end

    def self.me
      instance_id = Ec2InstanceData.instance_id
      region = Ec2InstanceData.region

      client = Aws::AutoScaling::Client.new(region: region)
      instance_info = client.describe_auto_scaling_instances({instance_ids: [instance_id]})
                            .auto_scaling_instances[0]

      new(
        group_name: instance_info.auto_scaling_group_name,
        id: instance_id,
        region: region
      )
    end

    def terminate(options = {})
      hook_name = options.delete(:continue_hook_name)
      raw.terminate(options)
      if hook_name
        sleep(terminate_wait_sleep_seconds) until terminating_wait?
        continue_to_termination(hook_name: hook_name)
      end
    end

    def unless_waiting_for_termination(hook_name:)
      # "Terminating" is a transition state to "Terminating:Wait", but we don't
      # check for it because if we try to continue from "Terminating", AWS freaks
      # out because it needs to continue from the wait state

      if terminating_wait?
        continue_to_termination(hook_name: hook_name)
        return
      end

      yield

      # In case the yield takes a long time and this code isn't called
      # again for a while (e.g. an infrequent cron job), check the terminating
      # state again.  If this method is called in a loop, the check here
      # and the next check at the start of this method will not cause duplicate
      # network calls because the lifecycle state is cached for a few seconds.

      if terminating_wait?
        continue_to_termination(hook_name: hook_name)
      end
    end

    def recent_lifecycle_state
      if @recent_lifecycle_state_last_refreshed_at.nil? ||
         Time.now - @recent_lifecycle_state_last_refreshed_at > lifecycle_state_refresh_seconds
        reload
        @recent_lifecycle_state_last_refreshed_at = Time.now
        @recent_lifecycle_state = lifecycle_state
      else
        @recent_lifecycle_state
      end
    end

    def lifecycle_state_refresh_seconds
      5
    end

    def terminate_wait_sleep_seconds
      6
    end

    def terminating_wait?
      "Terminating:Wait" == recent_lifecycle_state
    end

    def continue_to_termination(hook_name:)
      raw.client.complete_lifecycle_action({
        lifecycle_hook_name: hook_name,
        auto_scaling_group_name: raw.group_name,
        lifecycle_action_result: "CONTINUE",
        instance_id: raw.id,
      })
    end

  end
end
