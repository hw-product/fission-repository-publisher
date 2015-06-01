$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__)) + '/lib/'
require 'fission-repository-publisher/version'
Gem::Specification.new do |s|
  s.name = 'fission-repository-publisher'
  s.version = Fission::RepositoryPublisher::VERSION.version
  s.summary = 'Fission Repository Publisher'
  s.author = 'Heavywater'
  s.email = 'fission@hw-ops.com'
  s.homepage = 'http://github.com/heavywater/fission-repository-publisher'
  s.description = 'Publish repositories'
  s.require_path = 'lib'
  s.add_dependency 'fission'
  s.files = Dir['{lib}/**/**/*'] + %w(fission-repository-generator.gemspec README.md CHANGELOG.md)
end
