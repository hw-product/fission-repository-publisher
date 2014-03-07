require 'fission-repository-publisher'

module Fission
  module RepositoryPublisher
    class S3 < Fission::Callback

      attr_reader :object_store, :s3_store

      def setup(*args)
        @object_store = Fission::Assets::Store.new
        if(creds = Carnivore::Config.get(:fission, :repository_publisher, :credentials))
          if(Carnivore::Config.get(:fission, :repository_publisher, :domain))
            creds = creds.merge(:path_style => true)
            creds.delete(:region)
          end
          @s3_store = Fission::Assets::Store.new(creds.merge(:bucket => :none))
        else
          @s3_store = object_store
        end
      end

      def valid?(message)
        super do |payload|
          repos = retrieve(payload, :data, :repository_generator, :repositories)
          (Carnivore::Config.get(:fission, :repository_publisher, :target).to_s.downcase == 's3' ||
            retrieve(payload, :data, :repository_publisher, :target).to_s.downcase == 's3') &&
            ((repos && !repos.empty?) || retrieve(payload, :data, :repository_publisher, :repositories))
        end
      end

      def bucket_name(payload)
        if(Carnivore::Config.get(:fission, :repository_publisher, :domain))
          [retrieve(payload, :data, :account, :name),
            Carnivore::Config.get(:fission, :repository_publisher, :domain)].join('.')
        else
          [retrieve(payload, :data, :account, :name), 'package-store'].join('-')
        end
      end

      def working_directory(payload)
        base = Carnivore::Config.get(:fission, :repository_publisher, :working_directory) ||
          '/tmp/repository-publisher'
        File.join(base, payload[:message_id])
      end

      def execute(message)
        failure_wrap(message) do |payload|
          payload[:data][:repository_publisher] ||= {}
          s3_store.bucket = bucket_name(payload)
          [retrieve(payload, :data, :repository_publisher, :repositories),
            retrieve(payload, :data, :repository_generator, :repositories)].each do |item|
            if(item)
              (item.respond_to?(:values) ? item.values : item).each do |packed_key|
                asset = object_store.get(packed_key)
                repo_directory = File.join(working_directory(payload), File.basename(packed_key))
                Fission::Assets::Packer.unpack(asset, repo_directory)
                upload_objects(repo_directory)
              end
            end
            FileUtils.rm_rf(working_directory(payload))
          end
          if(public?(payload))
            site_endpoint = publish_bucket(bucket_name(payload))
            payload[:data][:repository_publisher][:endpoint] = site_endpoint
          end
          payload[:data][:repository_publisher][:s3_bucket_name] = bucket_name(payload)
          job_completed(:repository_publisher, payload, message)
        end
      end

      def upload_objects(repo_directory)
        debug "Processing repository directory: #{repo_directory}"
        Dir.glob(File.join(repo_directory, '**', '**', '*')).each do |file|
          next unless File.file?(file)
          object_key = file.sub(repo_directory, '').sub(/^\//, '')
          debug "Uploading repository item: [key: #{object_key}] [file: #{file}]"
          s3_store.put(object_key, file)
        end
      end

      def public?(payload)
        false
      end

      def publish_bucket(bucket_name)
        s3_store.connection.put_bucket_website(bucket_name)
        "http://#{bucket_name}"
      end
    end
  end
end

Fission.register(:repository_publisher, :publisher, Fission::RepositoryPublisher::S3)
