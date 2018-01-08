Gem::Specification.new do |gem|
  gem.name    = 'sensu-plugins-k8s'
  gem.version = '3.3.2'
  gem.date    = Date.today.to_s
  gem.summary = "Additional Sensu plugin to check Kubernetes resources"
  gem.license = 'MIT'
  gem.description = "Additional Sensu plugin to check Kubernetes resources"
  gem.authors  = ['Schuberg Philis']
  gem.email    = 'int-mcp@schubergphilis.com'
  gem.homepage = 'https://github.com/schubergphilis/sensu-plugins-k8s'
  gem.executables = ['check-k8s.rb']
end
