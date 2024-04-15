# frozen_string_literal: true

module Support
  module Parser
    def lexing_duration_for_graphql_version
      trace_lex_supported? ? Float::EPSILON : 0
    end

    def trace_lex_supported?
      # In GraphQL 2.2, the default parser was changed such that `lex` is no longer called
      @trace_lex_supported = Gem::Requirement.new("< 2.2").satisfied_by?(Gem::Version.new(GraphQL::VERSION)) ||
      using_c_parser?
    end

    def using_c_parser?
      defined?(GraphQL::CParser) == "constant"
    end
  end
end
