module OpenStax::Aws
  class PackerFactory

    # There are differences between Packer 1.2 and 1.4.  This factory attempts to
    # provide the right version of packer class.

    def self.new_packer(absolute_file_path:, dry_run: true)
      packer_version = `packer --version`

      raise "packer is not installed" if packer_version.nil?

      packer_class =
        case packer_version
        when /^1.2/
          Packer_1_2_5
        else
          Packer_1_4_1
        end

      @packer = packer_class.new(absolute_file_path: absolute_file_path,
                                 dry_run: dry_run)
    end

  end
end
