module OpenStax::Aws
  class Stack
    class Status
      def initialize(stack)
        @stack = stack
      end

      def status_text
        begin
          @stack.aws_stack.stack_status
        rescue Aws::CloudFormation::Errors::ValidationError => ee
          case ee.message
          when /Stack.*does not exist/
            self.class.does_not_exist_status_text
          else
            raise
          end
        end
      end

      def failed?
        self.class.failure_status_texts.include?(status_text)
      end

      def updating?
        %w(
          UPDATE_COMPLETE_CLEANUP_IN_PROGRESS
          UPDATE_IN_PROGRESS
          UPDATE_ROLLBACK_COMPLETE
          UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS
          UPDATE_ROLLBACK_FAILED
          UPDATE_ROLLBACK_IN_PROGRESS
        ).include?(status_text)
      end

      def creating?
        "CREATE_IN_PROGRESS" == status_text
      end

      def deleting?
        "DELETE_IN_PROGRESS" == status_text
      end

      def exists?
        self.class.does_not_exist_status_text != status_text
      end

      def self.does_not_exist_status_text
        "DOES_NOT_EXIST"
      end

      def self.all_status_texts
        %w(
          CREATE_IN_PROGRESS
          CREATE_FAILED
          CREATE_COMPLETE
          ROLLBACK_IN_PROGRESS
          ROLLBACK_FAILED
          ROLLBACK_COMPLETE
          DELETE_IN_PROGRESS
          DELETE_FAILED
          DELETE_COMPLETE
          UPDATE_IN_PROGRESS
          UPDATE_COMPLETE_CLEANUP_IN_PROGRESS
          UPDATE_COMPLETE
          UPDATE_ROLLBACK_IN_PROGRESS
          UPDATE_ROLLBACK_FAILED
          UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS
          UPDATE_ROLLBACK_COMPLETE
          REVIEW_IN_PROGRESS
          IMPORT_IN_PROGRESS
          IMPORT_COMPLETE
          IMPORT_ROLLBACK_IN_PROGRESS
          IMPORT_ROLLBACK_FAILED
          IMPORT_ROLLBACK_COMPLETE
        )
      end

      def self.active_status_texts
        all_status_texts - %w(CREATE_FAILED DELETE_COMPLETE)
      end

      def self.failure_status_texts
        %w(
          ROLLBACK_COMPLETE
          ROLLBACK_IN_PROGRESS
          CREATE_FAILED
          ROLLBACK_FAILED
          DELETE_FAILED
          UPDATE_ROLLBACK_FAILED
          IMPORT_ROLLBACK_FAILED
        )
      end

      def failed_events_since_last_user_event
        @stack.events.each_with_object([]) do |event, array|
          array.push(event) if event.failed? && event.status_reason  #if nil, don't push
          return array if event.user_initiated?
        end
      end

      def to_h
        {
          status: status_text,
          failed_events_since_last_user_event: failed? ? failed_events_since_last_user_event : []
        }
      end

      def to_json
        to_h.to_json
      end
    end
  end
end