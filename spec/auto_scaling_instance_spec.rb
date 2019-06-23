require 'spec_helper'
require 'vcr_helper'

RSpec.describe OpenStax::Aws::AutoScalingInstance, vcr: VCR_OPTS do

  # When this is true, the stack for testing already exists (useful for spinning up the stack)
  # and then not deleting it lets us rerun the specs over and over quickly.
  STACK_EXISTS = true

  context "me" do
    # When recordingthese specs, run them on an autoscaling instance within AWS (see
    # bin/create_development_environment).  The created instance will have the proper
    # permissions to make the `me` call using the instance credentials.  However, VCR
    # isn't set up to filter out these credentials, so just run them with your own
    # AWS keys, e.g.:
    #
    # $> VCR_OPTS_RECORD=all AWS_ACCESS_KEY_ID=foo AWS_SECRET_ACCESS_KEY=bar \
    #      bundle exec rspec ./spec/auto_scaling_instance_spec.rb:21

    it "makes an ASI" do
      expect(described_class.me.lifecycle_state).to eq "InService"
    end
  end

  context "terminate things" do

    before(:context) {
      OpenStax::Aws.configure do |config|
        config.cfn_template_bucket_name = "openstax-sandbox-cfn-templates"
        config.cfn_template_bucket_region = "us-west-2"
        config.stack_waiter_delay = 10
        config.fixed_s3_template_folder = "spec-templates"
      end

      # This stack gives us an ASG with an instance to test with
      @stack = new_stack(name: "rspec-asi2", filename: "auto_scaling_instance/app.yml")

      do_not_record_or_playback do
        @stack.create(params: {unique_name: "rspec-asi", image_id: ubuntu_ami}, wait: true) unless STACK_EXISTS
      end
    }

    after(:context) {
      do_not_record_or_playback { @stack.delete } unless STACK_EXISTS
    }

    before(:each) {
      # Eliminate variation in cached lifecycle state behavior during tests
      allow_any_instance_of(described_class).to receive(:lifecycle_state_refresh_seconds) { 0 }

      # Don't wait unnecessarily during playback
      allow_any_instance_of(described_class).to receive(:terminate_wait_sleep_seconds) { 0 } if !vcr_recording?

      # All of these specs are about terminating instances, so start with one instance
      set_desired_capacity_to_1
    }

    it "can get its lifecycle state" do
      expect(described_instance.lifecycle_state).to eq "InService"
    end

    it "can terminate and decrement desired capacity even with lifecycle hooks" do
      described_instance.terminate(should_decrement_desired_capacity: true,
                                   continue_hook_name: "TerminationHook")
      do_not_record_or_playback { sleep(20) }
      expect_instance_terminating_or_terminated
    end

    context "unless_waiting_for_termination" do
      it "will run once if not in termination wait" do
        test_object = double("test object")
        expect(test_object).to receive(:foo).once

        described_instance.unless_waiting_for_termination(hook_name: "TerminationHook") do
          test_object.foo
        end

        do_not_record_or_playback { sleep(20) }

        expect(described_instance.lifecycle_state).to eq "InService"
      end

      it "will not run and will continue if in termination wait before call" do
        test_object = double("test object")
        expect(test_object).not_to receive(:foo)

        set_desired_capacity_to_0
        described_instance.unless_waiting_for_termination(hook_name: "TerminationHook") do
          test_object.foo
        end

        do_not_record_or_playback { sleep(20) }

        expect_instance_terminating_or_terminated
      end

      it "will run and will continue if gets into termination wait during call" do
        test_object = double("test object")
        expect(test_object).to receive(:foo).once

        described_instance.unless_waiting_for_termination(hook_name: "TerminationHook") do
          test_object.foo
          do_not_record_or_playback { sleep(6) }
          set_desired_capacity_to_0
        end

        do_not_record_or_playback { sleep(20) }

        expect_instance_terminating_or_terminated
      end
    end
  end

  def expect_instance_terminating_or_terminated
    # instance may be gone by time we check, so look for that too
    instance = described_instance
    expect(instance.nil? ||
           ["Terminating:Proceed", "Terminated"].include?(instance.lifecycle_state)).to be true
  end

  def set_desired_capacity_to_1
    set_desired_capacity(count: 1, until_state: "InService")
  end

  def set_desired_capacity_to_0
    set_desired_capacity(count: 0, until_state: "Terminating:Wait")
  end

  def set_desired_capacity(count:, until_state:)
    asg.set_desired_capacity(desired_capacity: count)

    do_not_record_or_playback do
      while true do
        return if current_lifecycle_states == [until_state]
        sleep(10)
      end
    end
  end

  def current_lifecycle_states
    asg.instances.map(&:lifecycle_state)
  end

  def asg
    @stack.resource("Asg")
  end

  def described_instance
    asg = @stack.resource("Asg")
    id = asg.instances.first&.id

    return nil if id.nil?

    described_class.new(
      group_name: asg.name,
      id: id,
      region: SPEC_DEFAULT_REGION
    )
  end

  def ubuntu_ami
    # See bin/get_latest_ubuntu_ami
    "ami-0510c89f1a2691cf2"
  end

end
