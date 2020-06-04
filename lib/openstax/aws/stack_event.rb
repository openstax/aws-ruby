
require_relative 'stack_status'

module OpenStax::Aws
  class Stack
    class Event
      def initialize(aws_stack_event)
        @aws_stack_event = aws_stack_event
      end
    
      def status_text
        @aws_stack_event.data.resource_status
      end
    
      def status_reason
        @aws_stack_event.data.resource_status_reason
      end
    
      def failed?
        Status.failure_status_texts.include?(status_text)
      end
    
      def user_initiated?
        status_reason == "User Initiated"
      end
    end
  end
end