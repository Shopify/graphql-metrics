
# frozen_string_literal: true

module GraphQL
  module Metrics
    class Processor
      def initialize(query_or_multiplex, **options)
      end

      def field_extracted(field_metric, query:)
        raise NotImplementedError
      end

      def query_extracted(query_metrics, query:)
        raise NotImplementedError
      end

      def argument_extracted(argument_metric, query:)
        raise NotImplementedError
      end

      def directive_extracted(directive_metric, query:)
        raise NotImplementedError
      end
    end
  end
end
