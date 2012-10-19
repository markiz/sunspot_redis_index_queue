require 'active_support/core_ext/hash'
require 'redis'
require 'sunspot/redis_index_queue/ordered_heap'

module Sunspot
  module RedisIndexQueue
    class Client
      NO_LIMIT = 1_000_000

      # Wrapper around entry in an indexer queue
      # @private
      class Entry
        ATTRIBUTES = [
          :object_id, :object_class_name, :to_remove,
          :attempts_count, :run_at
        ].freeze

        def initialize(attributes = {})
          @attributes = default_attributes.merge(attributes.slice(*ATTRIBUTES))
        end

        def default_attributes
          HashWithIndifferentAccess.new({
            :to_remove      => false,
            :attempts_count => 0,
            :run_at         => Time.now
          })
        end

        def object
          @object ||= object_class_name.constantize.find(object_id)
        end

        def attributes
          @attributes
        end

        def marshal_dump
          @attributes
        end

        def marshal_load(attributes)
          @attributes = attributes
        end

        ATTRIBUTES.each {|k| define_method(k) { attributes[k] } }
        ATTRIBUTES.each {|k| define_method("#{k}=") {|v| attributes[k] = v } }

      end

      attr_reader :session, :heap, :options

      # Instantiate a new client session
      # @param [Sunspot::Session] session sunspot session that will receive the
      #     requests during processing
      # @option client_opts [String] "host" ("localhost") redis host name
      # @option client_opts [Integer] "port" (6379) redis port
      # @option client_opts [String] "password" (nil) redis password
      # @option client_opts [String] "sunspot_index_queue_name" ("sunspot_index_queue")
      #    redis index queue name
      # @option client_opts [Integer] "retry_interval" (300) time before next
      #    indexing attempt in case of failure / exception
      # @option client_opts [Integer] "max_attempts_count" (5) attempts count
      # @option client_opts [Integer] "index_delay" (0) delay in seconds between receiving
      #    a message about indexing and trying to process it
      # @api public
      def initialize(session, client_opts = {})
        @session = session
        @options = default_options.merge(client_opts)
        @redis   = Redis.connect(@options)
        @heap    = OrderedHeap.new(@redis, queue_name)
      end

      # @return [Integer] Number of pending jobs in the queue
      # @api public
      def count
        heap.count
      end

      # Send an object into queue for indexing
      # @param [Object] object item to process
      # @api public
      def index(object)
        entry = new_entry_for_object(object)
        add(entry)
      end

      # Send an object into queue for removing from index
      # @param [Object] object item to process
      # @api public
      def remove(object)
        entry = new_entry_for_object(object, :to_remove => true)
        add(entry)
      end

      # Adds an entry to the heap
      # @param [Entry]
      # @api semipublic
      def add(entry)
        heap.add(entry.run_at, entry)
      end

      # Extracts (gets and removes) entries scheduled for given time slice
      # @return [Array[Entry]]
      # @api semipublic
      def get(time_begin, time_end, limit = NO_LIMIT)
        heap.range!(time_begin, time_end, limit)
      end

      # Purges the queue
      # @api public
      def purge
        heap.purge
      end

      # Index or remove several entries from the queue.
      # @param [Integer] limit maximum number of entries to process
      # @return [Integer] number of entries processed
      # @api public
      def process(limit = 10)
        entries = get(Time.at(0), Time.now, limit)
        entries.each(&method(:process_entry)).count
      end

      # Reset bunny connection
      # @api semipublic
      def reset
      end

      # Index or remove an entry
      # @api semipublic
      def process_entry(entry)
        if entry.attempts_count < max_attempts_count
          if entry.to_remove
            session.remove_by_id(entry.object_class_name, entry.object_id)
          else
            session.index(entry.object)
          end
        end
      rescue => e
        if defined?(::Rails)
          ::Rails.logger.error "Exception raised while indexing: #{e.class}: #{e}"
        end
        entry.run_at = Time.now + retry_interval
        entry.attempts_count += 1
        add(entry)
      end

      # @api private
      def new_entry_for_object(object, extra_attributes = {})
        Entry.new({
          :object_id         => object.id,
          :object_class_name => object.class.name,
          :run_at            => Time.now + index_delay
        }.merge(extra_attributes))
      end


      # Number of failures allowed before being dropped from an index
      # queue altogether
      # @api semipublic
      def max_attempts_count
        options[:max_attempts_count]
      end

      # Interval in seconds before reindex is attempted after a failure.
      # @api semipublic
      def retry_interval
        options[:retry_interval]
      end

      # Index queue name
      # @api semipublic
      def queue_name
        options[:sunspot_index_queue_name] || options[:queue_name]
      end
      alias_method :heap_name, :queue_name

      # Delay between sending index command to sunspot session and
      # indexing
      # @api semipublic
      def index_delay
        options[:index_delay]
      end

      protected

      # List of default options ofr a client
      # @api semipublic
      def default_options
        HashWithIndifferentAccess.new({
          :host                     => "localhost",
          :port                     => 6379,
          :password                 => nil,
          :sunspot_index_queue_name => 'sunspot_index_queue',
          :retry_interval           => 300,
          :max_attempts_count       => 5,
          :index_delay              => 0
        })
      end

      # Gets a next available (with run_at < Time.now) entry out of the
      # queue. All the skipped entries are then pushed back into the queue.
      # @api semipublic
      def pop_next_available
        unused_entries = []
        result = nil
        while (entry = pop)
          if entry.run_at <= Time.now
            result = entry
            break
          else
            unused_entries << entry
          end
        end
        unused_entries.each {|e| push(e) }
        result
      end
    end
  end
end
