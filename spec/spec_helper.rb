require "rspec"
require "rspec/core"
require "rspec/mocks"
require "rspec/autorun"
require "sunspot"
require "sunspot_redis_index_queue"
require "yaml"

RSpec.configure do |c|
  c.mock_with :rspec
  c.before(:all) do
    $redis_config = HashWithIndifferentAccess.new(YAML.load_file("spec/redis.yml"))
  end

  c.before(:each) do
    $session = stub(:sunspot_session).as_null_object
    Sunspot.session = Sunspot::RedisIndexQueue::SessionProxy.new($session, $redis_config)
  end
end
