module Exporter
  class Server
    # Implements Shard (mongod) node role.
    class Shard < Exporter::Server
      def replica_name
        server.replica_set_name
      end

      def databases
        client.database_names - ['local'.freeze]
      end

      def fetch_metrics
        server_metrics + namespaces_metrics + replica_set_metrics
      end

      def server_metrics
        [Source::Mongod.new(raw_server_metrics, labels)]
      end

      def replica_set_metrics
        return [] unless replica?

        oplog_metrics = Collector::OpLog.new(self).to_h.merge! raw_oplog_metrics

        [Source::ReplicaSet.new(oplog_metrics, labels)]
      end

      def raw_server_metrics
        run(selector: { serverStatus: 1 }, db_name: 'admin')
      end

      def raw_oplog_metrics
        run(selector: { replSetGetStatus: 1 }, db_name: 'admin')
      end

      def namespaces_metrics
        databases.map do |database_name|
          namespace_metrics(database_name)
        end.flatten
      end

      def namespace_metrics(database_name)
        client.use(database_name).database.collection_names.map do |name|
          collections_metrics database_name, name
        end
      end

      def collections_metrics(database, name)
        collection_data = run(selector: { collStats: name }, db_name: database)
        index_data = collection_data.delete('indexDetails') { Hash.new }

        [
          indexes_metrics(database, name, index_data),
          collection_metric(database, name, collection_data)
        ]
      end

      def indexes_metrics(database, name, raw_data)
        raw_data.map do |index_name, index_raw_data|
          index_metric(database, name, index_name, index_raw_data)
        end
      end

      def collection_metric(database, name, raw_data)
        collection_labels = labels.merge db: database, coll: name

        Source::Collection.new(raw_data, collection_labels)
      end

      def index_metric(database, name, index_name, index_raw_data)
        index_labels = labels.merge db: database, coll: name, idx: index_name

        Source::Index.new(index_raw_data, index_labels)
      end

      def extra_labels
        { rs: replica_name }
      end

      def replica?
        features.include? :replica
      end
    end
  end
end
