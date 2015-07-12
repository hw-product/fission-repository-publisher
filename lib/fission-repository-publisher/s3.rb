require 'fission-repository-publisher'

module Fission
  module RepositoryPublisher
    class S3 < Fission::Callback

      # Determine message validity
      #
      # @param message [Carnivore::Message]
      # @return [Truthy, Falsey]
      def valid?(message)
        super do |payload|
          is_dest = payload.get(:data, :repository_publisher, :target).to_s == 's3' ||
            (payload.get(:data, :repository_publisher, :target).nil? && config.fetch(:target, 's3').to_s == 's3')
          is_dest && payload.get(:data, :repository_publisher, :repositories)
        end
      end

      # Publish repository to s3
      #
      # @param message [Carnivore::Message]
      def execute(message)
        failure_wrap(message) do |payload|
          payload.get(:data, :repository_publisher, :repositories).each do |type, pack|
            directory = File.join(working_directory(payload), type)
            packed_asset = asset_store.get(pack)
            asset_store.unpack(packed_asset, directory)
            upload_objects(payload, directory)
            payload.set(:data, :repository_publisher, :s3, type, true)
          end
          payload.fetch(:data, :repository_publisher, :package_assets, {}).each do |dest_key, source_key|
            asset = asset_store.get(source_key)
            asset_store.put(File.join(key_prefix(payload), dest_key), asset)
          end
          job_completed(:repository_publisher, payload, message)
        end
      end

      # Upload files to remote bucket
      #
      # @param repo_directory [String]
      # @return [TrueClass]
      def upload_objects(payload, repo_directory)
        Dir.glob(File.join(repo_directory, '**', '**', '*')).each do |file|
          debug "Processing repository file: #{file}"
          next unless File.file?(file)
          object_key = File.join(
            key_prefix(payload),
            file.sub(repo_directory, '').sub(/^\//, '')
          )
          debug "Uploading repository item: [key: #{object_key}] [file: #{file}]"
          asset_store.put(object_key, file)
        end
        true
      end

      # Generate common storage key prefix based on payload
      # information
      #
      # @param payload [Smash]
      # @return [String] key prefix
      def key_prefix(payload)
        object_key = File.join(
          config.fetch(:bucket_prefix, 'published-repositories'),
          payload.get(:data, :account, :name)
        )
      end

    end
  end
end

Fission.register(:repository_publisher, :publisher, Fission::RepositoryPublisher::S3)
