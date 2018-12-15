module OpenStax::Aws
  class ChangeSetDescription

    attr_reader :aws_struct

    def initialize(aws_struct)
      @aws_struct = aws_struct
    end

    def has_change_caused_by?(entity_name)
      aws_struct.changes.any? do |change|
        change.resource_change.details.any? do |detail|
          detail.causing_entity == entity_name
        end
      end
    end

    def change_summaries
      summaries = aws_struct.changes.flat_map(&:resource_change).map do |change|
        summary = "#{change.action} '#{change.logical_resource_id}' (#{change.resource_type})"

        case change.action
        when "Modify"
          causes = change.details.map{|detail| [detail.change_source, detail.causing_entity].compact.join(":")}.join(", ")

          summary = "#{summary}: Replacement=#{change.replacement}; Due to change in #{change.scope}; Causes: #{causes}"
        end

        summary
      end
    end
  end
end
