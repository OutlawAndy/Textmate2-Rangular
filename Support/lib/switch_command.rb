require "fileutils"

module Outlaw
  module Mate
    module Helpers
      def base_dir
        ENV['TM_PROJECT_DIRECTORY'] || File.dirname(ENV['TM_FILEPATH'])
      end
    end
  end
end


module Outlaw
  module Mate
    class SwitchCommand
      include Helpers

      def go_to_twin(project_directory, filepath)
        other = twin(filepath)

        if File.file?(other)
          `"$TM_SUPPORT_PATH/bin/mate" "#{other}"`
        else
          relative  = other[project_directory.length + 1..-1]
          file_type = file_type(other)

          write_and_open(other) if create?(relative, file_type)
        end
      end

      module Framework
        def merb?
          File.exist?(File.join(self, 'config', 'init.rb'))
        end

        def merb_or_rails?
          merb? || rails?
        end

        def rails?
          File.exist?(File.join(self, 'config', 'boot.rb'))
        end
      end

      def twin(path)
        return unless path =~ %r{^(.*?)/(lib|app|test)/(.*?)$}
        framework = Regexp.last_match(1)
        parent = Regexp.last_match(2)
        framework.extend Framework

        case parent
        when 'lib', 'app' then
          if framework.merb_or_rails?
            if path.include?("/app/lib/")
              path = path.gsub("/app/lib/", "/test/app/lib/")
            else
              path = path.gsub(%r{/app/}, "/test/")
              path = path.gsub(%r{/lib/}, "/test/lib/")
            end
          else
            path = path.gsub(%r{/lib/}, "/test/")
          end

          path = path.gsub(/\.rb$/, "_test.rb")
          path = path.gsub(/\.erb$/, ".erb_test.rb")
          path = path.gsub(/\.haml$/, ".haml_test.rb")
          path = path.gsub(/\.slim$/, ".slim_test.rb")
          path = path.gsub(/\.rhtml$/, ".rhtml_test.rb")
          path = path.gsub(/\.rjs$/, ".rjs_test.rb")
        when 'test' then
          path = path.gsub(/\.rjs_test\.rb$/, ".rjs")
          path = path.gsub(/\.rhtml_test\.rb$/, ".rhtml")
          path = path.gsub(/\.erb_test\.rb$/, ".erb")
          path = path.gsub(/\.haml_test\.rb$/, ".haml")
          path = path.gsub(/\.slim_test\.rb$/, ".slim")
          path = path.gsub(/_test\.rb$/, ".rb")

          if framework.merb_or_rails?
            if path.include?("/test/app/lib/")
              path = path.gsub("/test/app/lib/", "/app/lib/")
            else
              path = path.gsub(%r{/test/lib/}, "/lib/")
              path = path.gsub(%r{/test/}, "/app/")
            end
          else
            path = path.gsub(%r{/test/}, "/lib/")
          end
        end

        path
      end

      def file_type(path)
        case path
        when %r{^(.*?)/(test)/(controllers|helpers|models|views)/(.*?)$}
          "#{Regexp.last_match(3)[0..-2]} test"
        when %r{^(.*?)/(app)/(controllers|helpers|models|views)/(.*?)$}
          Regexp.last_match(3)[0..-2]
        when /_test\.rb$/
          "test"
        else
          "file"
        end
      end

      def create?(relative_twin, file_type)
        cmd = %('#{ENV['TM_SUPPORT_PATH']}/bin/CocoaDialog.app/Contents/MacOS/CocoaDialog') +
              %( yesno-msgbox --no-cancel --icon document --informative-text "#{relative_twin}") +
              %( --text "Create missing #{file_type}?")
        answer = `#{cmd}`
        answer.to_s.chomp == "1"
      end

      def class_from_path(path)
        underscored = path.split('/').last.split('.rb').first
        parts = underscored.split('_')

        parts.inject("") do |word, part|
          word << part.capitalize
          word
        end
      end

      def klass(relative_path, _content=nil)
        parts     = relative_path.split('/')
        lib_index = parts.index('lib') || 0
        parts     = parts[lib_index + 1..-1]
        lines     = Array.new(parts.length * 2)

        parts.each_with_index do |part, n|
          part   = part.capitalize
          indent = "  " * n

          line = if part =~ /(.*)\.rb/
                   part = Regexp.last_match(1)
                   "#{indent}class #{part}"
                 else
                   "#{indent}module #{part}"
                 end

          lines[n] = line
          lines[lines.length - (n + 1)] = "#{indent}end"
        end

        lines.join("\n") + "\n"
      end

      def write_and_open(path)
        FileUtils.mkdir_p(File.dirname(path))
        described = described_class_for(path, base_dir)
        use_rails_helper = File.exist? "#{base_dir}/test/rails_helper.rb"
        File.open(path, 'w') do |f|
          f.puts "require '#{use_rails_helper ? :rails_helper : :test_helper}'"
          f.puts ''
          f.puts "describe #{described} do"
          f.puts '  ' # <= caret will be here
          f.puts 'end'
        end
        system ENV['TM_SUPPORT_PATH'] + '/bin/mate', path, '-l4:3'
      end

      def described_class_for(path, base_path)
        relative_path = path[base_path.size..-1]
        camelize = lambda { |part| part.gsub(/_([a-z])/) { Regexp.last_match(1).upcase }.gsub(/^([a-z])/) { Regexp.last_match(1).upcase } }
        parts = File.dirname(relative_path).split('/').compact.reject(&:empty?)
        parts.shift if parts[0] == 'app'
        parts.shift if parts[0] == 'test' && %w[controllers helpers models views].include?(parts[1])

        described = Array(parts[1..-1]).map(&camelize)
        described << camelize.call(File.basename(path, '_test.rb').split('.').first)
        described = described.compact.reject(&:empty?).join('::')
        described
      end
    end
  end
end
