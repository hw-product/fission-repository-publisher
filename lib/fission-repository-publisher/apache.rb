require 'fission-repository-publisher'

module Fission
  module RepositoryPublisher
    class Apache < Fission::Callback

      include Fission::Utils::Dns

      attr_reader :object_store

      def setup(*args)
        require 'webrick/httpauth'
        require 'tempfile'
        require 'fileutils'
        @object_store = Fission::Assets::Store.new
      end

      def valid?(message)
        super do |payload|
          repos = retrieve(payload, :data, :repository_generator, :repositories)
          (Carnivore::Config.get(:fission, :repository_publisher, :target).to_s.downcase == 'apache' ||
            retrieve(payload, :data, :repository_publisher, :target).to_s.downcase == 'apache') &&
            ((repos && !repos.empty?) || retrieve(payload, :data, :repository_publisher, :repositories))
        end
      end

      def repository_directory(payload)
        path = File.join(
          Carnivore::Config.get(:fission, :repository_publisher, :apache, :base_directory) || "/opt/apache-repositories",
          retrieve(payload, :data, :account)
        )
        unless(File.directory?(path))
          FileUtils.mkdir_p(path)
        end
        path
      end

      def repositories_metadata(payload)
        [
          retrieve(payload, :data, :repository_generator, :repositories),
          retrieve(payload, :data, :repository_publisher, :repositories),
          Carnivore::Config.get(:fission, :repository_publisher, :repositories)
        ].compact
      end

      def execute(message)
        failure_wrap(message) do |payload|
          target_directory = repository_directory(payload)
          repositories_metadata(payload).each do |item|
            (item.respond_to?(:values) ? item.values : item).each do |packed_key|
              asset = object_store.get(packed_key)
              repo_directory = File.join(target_directory, File.basename(packed_key))
              Fission::Assets::Packer.unpack(asset, repo_directory)
            end
          end
          write_access_file(payload, target_directory)
          point_dns(payload) # This should probably be a call to
          # separate component
          payload[:data][:repository_publisher][:apache_directory] = target_directory
          job_completed(:repository_publisher, payload, message)
        end
      end

      def setup_access(payload, directory)
        credential_path = File.join(
          Carnivore::Config.get(:fission, :repository_publisher, :apache, :credential_directory),
          "#{File.dirname(directory)}.htpasswd"
        )
        tmp = Tempfile.new('apache-publisher')
        begin
          htpasswd = WEBrick::HTTPAuth::Htpasswd.new(tmp.path)
          [retrieve(payload, :account, :tokens, :repository)].flatten.compact.each do |token|
            htpasswd.set_passwd(retrieve(payload, :account, :name), token)
          end
          htpasswd.flush
          File.open(credential_path, 'w+') do |file|
            file.write File.read(tmp.path)
          end
        ensure
          tmp.close
          tmp.unlink
        end
        tmp = Tempfile.new('apache-publisher-access')
        begin
          tmp.puts [
            "AuthUserFile #{credential_path}"
            'AuthName "Authorization Required"',
            'AuthType Basic',
            'require valid-user'
          ].join("\n")
          tmp.flush
          File.open(File.join(directory, '.htaccess'), 'w+') do |file|
            file.write File.read(tmp.path)
          end
        ensure
          tmp.close
          tmp.unlink
        end
      end

      def point_dns(payload, endpoint = false)
        if(Carnivore::Config.get(:fission, :repository_publisher, :dns, :enabled) &&
            Carnovire::Config.get(:fission, :repository_publisher, :domain))
          zone = dns.zones.detect{|z| z.domain == Carnivore::Config.get(:fission, :repository_publisher, :domain)}
          record_name = retrieve(payload, :data, :account, :name)
          existing = zone.records.detect{|record| record.name == record_name}
          if(existing)
            existing.name = record_name
            existing.type = 'CNAME'
            existing.value = endpoint ||
              Carnivore::Config.get(:fission, :repository_publisher, :dns, :apache_endpoint) ||
              Carnivore::Config.get(:fission, :repository_publisher, :dns, :default_endpoint)
          else
            zone.records.create(
              :name => record_name,
              :type => 'CNAME',
              :value => endpoint ||
                Carnivore::Config.get(:fission, :repository_publisher, :dns, :apache_endpoint) ||
                Carnivore::Config.get(:fission, :repository_publisher, :dns, :default_endpoint)
            )
          end
          payload[:data][:repository_publisher][:dns] = [record_name, zone.domain].join('.')
        end
      end

    end
  end
end

Fission.register(:repository_publisher, :publisher, Fission::RepositoryPublisher::Apache)
