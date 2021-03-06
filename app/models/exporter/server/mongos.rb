module Exporter
  class Server
    # Implements Shard Router node role
    class Mongos < Exporter::Server
      def fetch_metrics
        [Exporter::Source::Mongos.new(raw_metrics, labels)]
      end

      def raw_metrics
        run(selector: { serverStatus: 1 }, db_name: 'admin')
      end
    end
  end
end
