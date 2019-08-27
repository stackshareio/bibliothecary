require 'json'

module Bibliothecary
  module Parsers
    class Conda
      include Bibliothecary::Analyser
      FILE_KINDS = %i[manifest lockfile]

      def self.mapping
        {
          match_filename("environment.yml") => {
            kind: FILE_KINDS
          },
          match_filename("environment.yaml") => {
            kind: FILE_KINDS
          }
        }
      end

      # Overrides Analyser.analyse_contents_from_info
      def self.analyse_contents_from_info(info)
        results = call_conda_parser_web(info.contents)

        analyses = FILE_KINDS.map do |kind|
          Bibliothecary::Analyser.create_analysis(
            "conda",
            info.relative_path,
            kind.to_s,
            results[kind].map { |dep| dep.slice(:name, :requirement).merge(type: "runtime") }
          )
        end

        pip_dependencies = parse_pip(info)
        analyses <<  pip_dependencies if pip_dependencies

        analyses
      rescue Bibliothecary::RemoteParsingError => e
        Bibliothecary::Analyser::create_error_analysis(platform_name, info.relative_path, "runtime", e.message)
      end

      private

      def self.parse_pip(info)
        dependencies = YAML.load(info.contents).dig("dependencies")
        pip = dependencies.find { |dep| dep.is_a?(Hash) && dep.dig("pip")}
        return nil unless pip

        Bibliothecary::Analyser.create_analysis(
          "pypi",
          info.relative_path,
          "manifest",
          Pypi.parse_requirements_txt(pip["pip"].join("\n"))
        )
      end

      def self.call_conda_parser_web(file_contents)
        host = Bibliothecary.configuration.conda_parser_host
        response = Typhoeus.post(
          "#{host}/parse",
          headers: {
              ContentType: 'multipart/form-data'
          },
          # hardcoding `environment.yml` to send to `conda.libraries.io`, downside is logs will always show `environment.yml` there
          body: {file: file_contents, filename: 'environment.yml'}
        )
        raise Bibliothecary::RemoteParsingError.new("Http Error #{response.response_code} when contacting: #{host}/parse", response.response_code) unless response.success?

        JSON.parse(response.body, symbolize_names: true)
      end
    end
  end
end
