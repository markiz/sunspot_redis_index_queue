# -*- encoding: utf-8 -*-
require File.expand_path('../lib/sunspot/redis_index_queue/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Mark Abramov"]
  gem.email         = ["markizko@gmail.com"]
  gem.description   = "Asynchronously handle your sunspot model indexing"
  gem.summary       = "Asynchronously handle your sunspot model indexing"
  gem.homepage      = "https://github.com/markiz/sunspot_redis_index_queue"

  gem.add_dependency "sunspot"
  gem.add_dependency "redis"
  gem.add_dependency "activesupport", ">= 3.0.0"

  # testing
  gem.add_development_dependency "sunspot_solr"
  gem.add_development_dependency "rspec"

  # documentation
  gem.add_development_dependency "yard"
  gem.add_development_dependency "kramdown"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "sunspot_redis_index_queue"
  gem.require_paths = ["lib"]
  gem.version       = Sunspot::RedisIndexQueue::VERSION
end
