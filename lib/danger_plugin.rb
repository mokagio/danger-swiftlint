module Danger

  # Lint Swift files inside your projects.
  # This is done using the [SwiftLint](https://github.com/realm/SwiftLint) tool.
  # Results are passed out as a table in markdown.
  #
  # @example Specifying custom config file.
  #
  #          # Runs a linter with comma style disabled
  #          swiftlint.config_file = '.swiftlint.yml'
  #          swiftlint.lint_files
  #
  # @see  artsy/eigen
  # @tags swift
  #
  class DangerSwiftlint < Plugin

    # Allows you to specify a config file location for swiftlint.
    attr_accessor :config_file

    # Allows you to specify a directory from where swiftlint will be run. 
    attr_accessor :directory

    # Lints Swift files. Will fail if `swiftlint` cannot be installed correctly.
    # Generates a `markdown` list of warnings for the prose in a corpus of .markdown and .md files. 
    #
    # @param   [String] files
    #          A globbed string which should return the files that you want to lint, defaults to nil.
    #          if nil, modified and added files from the diff will be used.
    # @return  [void]
    #
    def lint_files(files=nil)
      # Installs SwiftLint if needed
      system "brew install swiftlint" unless swiftlint_installed?

      # Check that this is in the user's PATH after installing
      unless swiftlint_installed?
        fail "swiftlint is not in the user's PATH, or it failed to install"
        return
      end

      require 'tempfile'
      Tempfile.open('.swiftlint_danger.yml') do |temp_config_file|
        on_the_fly_configuration_path = nil
        if config_file
          require 'yaml'
          original_config = YAML.load_file(config_file)

          danger_compatible_config = original_config
          danger_compatible_config.tap { |hash| hash.delete('included') }

          File.write(temp_config_file.path, danger_compatible_config.to_yaml)

          on_the_fly_configuration_path = temp_config_file.path
        end

        swiftlint_command = "swiftlint lint --quiet --reporter json"
        swiftlint_command += " --config #{on_the_fly_configuration_path}" if on_the_fly_configuration_path

        require 'json'

        if directory
          swiftlint_command = "cd #{directory} && #{swiftlint_command}" if directory

          result_json = JSON.parse(`(#{swiftlint_command})`).flatten
        else
          # Either use files provided, or use the modified + added
          swift_files = files ? Dir.glob(files) : (git.modified_files + git.added_files)
          swift_files.select! do |line| line.end_with?(".swift") end

          # Make sure we don't fail when paths have spaces
          swift_files = swift_files.map { |file| "\"#{file}\"" }

          result_json = swift_files
          .uniq
          .collect { |f| `(#{swiftlint_command} --path #{f})`.strip }
          .reject { |s| s == '' }
          .map { |s| JSON.parse(s).flatten }
          .flatten
        end

        # Convert to swiftlint results
        warnings = result_json.select do |results|
          results['severity'] == 'Warning'
        end
        errors = result_json.select do |results|
          results['severity'] == 'Error'
        end

        warnings.each do |warning|
          location = warning['file'].gsub(Dir.pwd, '')
          warn(warning['type'], sticky: true, file: location, line: warning['line'])
        end
        errors.each do |error|
          location = error['file'].gsub(Dir.pwd, '')
          fail(error['type'], sticky: true, file: location, line: error['line'])
        end
      end
    end

    # Determine if swiftlint is currently installed in the system paths.
    # @return  [Bool]
    #
    def swiftlint_installed?
      `which swiftlint`.strip.empty? == false
    end
  end
end
