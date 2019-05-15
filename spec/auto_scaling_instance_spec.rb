require 'spec_helper'
require 'vcr_helper'

RSpec.describe OpenStax::Aws::AutoScalingInstance, vcr: VCR_OPTS do

  REGION = 'us-east-2'

  STACK_EXISTS = true

  context "terminate things" do

    before(:context) {
      OpenStax::Aws.configure do |config|
        config.cfn_template_bucket_name = "openstax-sandbox-cfn-templates"
        config.cfn_template_bucket_region = "us-west-2"
        config.stack_waiter_delay = 10
        config.fixed_s3_template_folder = "spec-templates"
      end

      @stack = new_stack(name: "rspec-asi2", filename: "app.yml")

      do_not_record_or_playback do
        @stack.create(params: {unique_name: "rspec-asi", image_id: ubuntu_ami}, wait: true) unless STACK_EXISTS
      end
    }

    after(:context) {
      do_not_record_or_playback { @stack.delete } unless STACK_EXISTS
    }

    around(:each) do |example|
      original_logger = OpenStax::Aws.configuration.logger
      example.run
      OpenStax::Aws.configuration.logger = original_logger
    end

    before(:each) {
      @logger = spy("logger")
      OpenStax::Aws.configuration.logger = @logger

      # Eliminate variation in cached lifecycle state behavior during tests
      allow_any_instance_of(described_class).to receive(:lifecycle_state_refresh_seconds) { 0 }

      # Don't wait unnecessarily during playback
      allow_any_instance_of(described_class).to receive(:terminate_wait_sleep_seconds) { 0 } if !vcr_recording?
    }

    it "can get its lifecycle state" do
      set_desired_capacity_to_1

      expect(described_instance.lifecycle_state).to eq "InService"
    end

    it "can terminate and decrement desired capacity even with lifecycle hooks" do
      set_desired_capacity_to_1
      described_instance.terminate(should_decrement_desired_capacity: true,
                                   continue_hook_name: "TerminationHook")
      do_not_record_or_playback { sleep(20) }
      expect_instance_terminating_or_terminated
    end

    context "unless_waiting_for_termination" do
      before { set_desired_capacity_to_1 }

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
      region: REGION
    )
  end

  def new_stack(name:, filename:, overrides: {})
    OpenStax::Aws::Stack.new(
      {
        name: name,
        region: REGION,
        absolute_template_path: File.join(__dir__, "support/templates/auto_scaling_instance/#{filename}"),
        dry_run: false,
      }.merge(overrides)
    )
  end

  def ubuntu_ami
    # See bin/get_latest_ubuntu_ami
    "ami-0510c89f1a2691cf2"
  end

end
