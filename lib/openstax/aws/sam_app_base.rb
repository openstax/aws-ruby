module OpenStax::Aws
  class SamAppBase

    attr_reader :dry_run

    def initialize(dry_run: true)
      @dry_run = dry_run
    end

    def built_template_filename
      "template.yaml" # AFAIK this cannot be changed
    end

    def packaged_template_filename
      "app-output-sam.yaml"
    end

    class << self
      def source_template_file(*path_parts)
        if method_defined?("source_template_file")
          raise "Can only set source_template_file once per class definition"
        end

        define_method "source_template_file" do
          File.expand_path(File.join(*path_parts))
        end
      end

      def build_directory(*directory_parts)
        if method_defined?("build_directory")
          raise "Can only set build_directory once per class definition"
        end

        define_method "build_directory" do
          File.expand_path(File.join(*directory_parts))
        end
      end

      def packaged_template_filename(filename)
        define_method "packaged_template_filename" do
          filename
        end
      end
    end

    def build
      command = "sam build -t #{source_template_file} -b #{build_directory}"
      System.call(command, logger: logger, dry_run: dry_run)
    end

    def package(bucket:)
      command = "sam package --s3-bucket #{bucket}" \
                " --template-file #{built_template_file}" \
                " --output-template-file #{packaged_template_file}"
      System.call(command, logger: logger, dry_run: dry_run)
    end

    def built_template_file
      "#{build_directory}/#{built_template_filename}"
    end

    def packaged_template_file
      "#{build_directory}/#{packaged_template_filename}"
    end

    def method_missing(method, *args, &block)
      case method.to_sym
      when :source_template_file
        raise "You must set the source template file with a call to " \
              "`source_template_file` in #{self.class.name}"
      when :build_directory
        raise "You must set the build directory with a call to `build_directory` " \
              "in #{self.class.name}"
      else
        super
      end
    end

    delegate :logger, to: :configuration

    def configuration
      OpenStax::Aws.configuration
    end

  end
end
