module Sunspot
  module RedisIndexQueue
    class OrderedHeap
      NO_LIMIT = 1_000_000

      attr_reader :redis, :name

      def initialize(redis, name)
        @redis, @name = redis, name
      end

      def add(score, value)
        redis.zadd(name, score.to_i, serialize(value))
      end

      def range(score_begin, score_end, limit = NO_LIMIT)
        redis.zrangebyscore(name, score_begin.to_i, score_end.to_i, :limit => [0, limit]).map {|value| unserialize(value) }
      end

      def range!(score_begin, score_end, limit = NO_LIMIT)
        redis.synchronize do
          result = redis.zrangebyscore(name, score_begin.to_i, score_end.to_i, :limit => [0, limit])
          if result.count > 0
            redis.zrem(name, result)
          end
          result.map {|item| unserialize(item) }
        end
      end

      def remove(score)
        range!(score, score)
      end

      def purge
        redis.zremrangebyrank(name, 0, -1)
      end

      def count
        redis.zcard(name)
      end

      private

      def serialize(object)
        Marshal.dump(object)
      end

      def unserialize(data)
        Marshal.load(data)
      end
    end
  end
end
