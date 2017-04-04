require 'fileutils'
require 'paperclip'

module Paperclip
  module Nginx
    module Upload
      class TmpPathNotInWhitelistError < StandardError
        def initialize(tmp_path, whitelist)
          super("Paperclip nginx upload adapter received non whitelisted tmp file '#{tmp_path}'. " +
                "Whitelist: #{whitelist.inspect}")
        end
      end

      class IOAdapter < Paperclip::AbstractAdapter
        # Paperclip < 3.3.1 compatibility
        unless Paperclip::AbstractAdapter.instance_methods.include?(:original_filename=)
          attr_writer(:original_filename)
        end

        def initialize(target, options = {})
          @target = target
          @options = self.class.default_options.merge(options)

          require_whitelist_match!(@target[:tmp_path])
          cache_current_values
        end

        def self.default_options
          @default_options ||= {
            :tmp_path_whitelist => [],
            :move_tempfile => false
          }
        end

        private

        def require_whitelist_match!(path)
          unless matches_whitelist?(File.expand_path(path))
            raise TmpPathNotInWhitelistError.new(path, tmp_path_whitelist)
          end
        end

        def matches_whitelist?(path)
          tmp_path_whitelist.any? do |glob|
            File.fnmatch(glob, path)
          end
        end

        def tmp_path_whitelist
          @options[:tmp_path_whitelist]
        end

        def cache_current_values
          self.original_filename = @target[:original_name]
          @content_type = @target[:content_type].to_s.strip
          @size = File.size(@target[:tmp_path])

          copy_or_move(@target[:tmp_path], destination.path)
          @tempfile = destination

          # Required to reopen the tempfile that we have overwritten
          @tempfile.open
          @tempfile.binmode
        end

        def copy_or_move(source_path, destination_path)
          if @options[:move_tempfile]
            FileUtils.mv(@target[:tmp_path], destination.path)
          else
            FileUtils.cp(@target[:tmp_path], destination.path)
          end
        end
      end
    end
  end
end

Paperclip.io_adapters.register Paperclip::Nginx::Upload::IOAdapter do |target|
  keys = [:original_name, :content_type, :tmp_path]
  target = target.permit(keys).to_h if ActionController::Parameters === target
  Hash === target && keys.all? { |key| target.key?(key) }
end
