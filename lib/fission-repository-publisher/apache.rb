# require 'fission-repository-publisher'

# module Fission
#   module RepositoryPublisher
#     class Httpd < Fission::Callback

#       include Fission::Utils::Dns

#       # Run required setup for callback
#       def setup(*args)
#         require 'webrick/httpauth'
#         require 'tempfile'
#         require 'fileutils'
#       end

#       # Determine validity of message
#       #
#       # @param message [Carnivore::Message]
#       # @return [Truthy, Falsey]
#       def valid?(message)
#         super do |payload|
#           is_dest = payload.get(:data, :repository_publisher, :target).to_s == 'httpd' ||
#             (payload.get(:data, :repository_publisher, :target).nil? && config[:target].to_s == 'httpd')
#           is_dest && payload.get(:data, :repository_publisher, :repositories)
#         end
#       end

#       # Destination directory for repository
#       #
#       # @param payload [Smash]
#       # @return [String] path
#       def repository_directory(payload)
#         path = File.join(
#           config.fetch(:httpd, :destination_directory, '/opt/fission-repositories'),
#           payload.fetch(:data, :account, :name, 'default')
#         )
#         unless(File.directory?(path))
#           FileUtils.mkdir_p(path)
#         end
#         path
#       end

#       # Install repository to local directory
#       #
#       # @param message [Carnivore::Message]
#       def execute(message)
#         failure_wrap(message) do |payload|
#           target_directory = repository_directory(payload)
#           payload.get(:data, :repository_publisher, :repositories).each do |repo_type, packed_key|
#             destination = File.join(repository_directory(payload), repo_type)
#             FileUtils.rm_rf(destination)
#             asset_store.unpack(asset_store.get(packed_key), destination)
#           end
#           write_access_file(payload, repository_directory(payload))
#           point_dns(payload) # This should probably be a call to
#           # separate component
#           payload.set(:data, :repository_publisher, :httpd, :installed, repository_directory(payload))
#           job_completed(:repository_publisher, payload, message)
#         end
#       end

#       def write_access_file(payload, directory)
#         credential_path = File.join(
#           Carnivore::Config.get(:fission, :repository_publisher, :apache, :credential_directory),
#           "#{File.dirname(directory)}.htpasswd"
#         )
#         tmp = Tempfile.new('apache-publisher')
#         begin
#           htpasswd = WEBrick::HTTPAuth::Htpasswd.new(tmp.path)
#           [retrieve(payload, :account, :tokens, :repository)].flatten.compact.each do |token|
#             htpasswd.set_passwd(retrieve(payload, :account, :name), token)
#           end
#           htpasswd.flush
#           File.open(credential_path, 'w+') do |file|
#             file.write File.read(tmp.path)
#           end
#         ensure
#           tmp.close
#           tmp.unlink
#         end
#         tmp = Tempfile.new('apache-publisher-access')
#         begin
#           tmp.puts [
#             "AuthUserFile #{credential_path}"
#             'AuthName "Authorization Required"',
#             'AuthType Basic',
#             'require valid-user'
#           ].join("\n")
#           tmp.flush
#           File.open(File.join(directory, '.htaccess'), 'w+') do |file|
#             file.write File.read(tmp.path)
#           end
#         ensure
#           tmp.close
#           tmp.unlink
#         end
#       end

#       def point_dns(payload, endpoint = false)
#         if(Carnivore::Config.get(:fission, :repository_publisher, :dns, :enabled) &&
#             Carnovire::Config.get(:fission, :repository_publisher, :domain))
#           zone = dns.zones.detect{|z| z.domain == Carnivore::Config.get(:fission, :repository_publisher, :domain)}
#           record_name = retrieve(payload, :data, :account, :name)
#           existing = zone.records.detect{|record| record.name == record_name}
#           if(existing)
#             existing.name = record_name
#             existing.type = 'CNAME'
#             existing.value = endpoint ||
#               Carnivore::Config.get(:fission, :repository_publisher, :dns, :apache_endpoint) ||
#               Carnivore::Config.get(:fission, :repository_publisher, :dns, :default_endpoint)
#           else
#             zone.records.create(
#               :name => record_name,
#               :type => 'CNAME',
#               :value => endpoint ||
#                 Carnivore::Config.get(:fission, :repository_publisher, :dns, :apache_endpoint) ||
#                 Carnivore::Config.get(:fission, :repository_publisher, :dns, :default_endpoint)
#             )
#           end
#           payload[:data][:repository_publisher][:dns] = [record_name, zone.domain].join('.')
#         end
#       end

#     end
#   end
# end

# Fission.register(:repository_publisher, :publisher, Fission::RepositoryPublisher::Apache)
