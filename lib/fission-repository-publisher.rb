require 'fission'
require 'fission-repository-publisher/s3'
# require 'fission-repository-publisher/apache'
require 'fission-repository-publisher/version'

Fission.service(
  :repository_publisher,
  :description => 'Publish repositories for consumption',
  :configuration => {
    :public_bucket => {
      :type => :string,
      :description => 'Public bucket to publish repository'
    }
  }
)
