# Redis Index Queue for sunspot

Asynchronously index your sunspot models.

## Rationale and influences

This library is heavily influenced by [https://github.com/bdurand/sunspot_index_queue](sunspot_index_queue) gem.

## Installation

Add this line to your application's Gemfile:

    gem 'sunspot_redis_index_queue'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sunspot_redis_index_queue

## Usage

There are two parts to asynchronous indexer, first is a proxy that sends
all index/remove requests to a queue:


    # Somewhere in an initializer (for Rails) / before your code starts
    require 'sunspot_redis_index_queue'
    redis_config = {
      "host"       => "localhost",
      "port"       => 6379,
      "queue_name" => "indexer_queue"
    }
    # Implies that Sunspot.session is already initialized as your real sunspot
    # session
    Sunspot.session = Sunspot::RedisIndexQueue::SessionProxy.new(Sunspot.session, redis_config)


Second part is an indexing daemon that handles processing. It boils down to


    # ... require environment

    loop do
      Sunspot.session.client.process(20) # process 20 entries
      sleep(1)
    end

## Thread-safety

It should be safe to use a threaded solution for an indexer.


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License

This library is in [public domain](http://unlicense.org/UNLICENSE).
