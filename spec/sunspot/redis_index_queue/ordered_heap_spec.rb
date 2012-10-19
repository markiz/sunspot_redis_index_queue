# encoding: utf-8
require "spec_helper"

describe Sunspot::RedisIndexQueue::OrderedHeap do
  Point = Struct.new(:x, :y)

  let(:redis) { Redis.connect($redis_config) }
  let(:heap_name) { 'redis_index_queue:test_heap' }
  subject { described_class.new(redis, heap_name) }

  before { redis.zremrangebyrank(heap_name, 0, -1) }

  describe "#add" do
    it "adds a zkey to redis" do
      t = Time.now
      subject.add(t, 'hello, world')
      redis.zcard(heap_name).should == 1
      redis.zrange(heap_name, 0, 0).first.should == Marshal.dump('hello, world')
    end
  end

  describe "#range" do
    before do
      subject.add(0, "hello")
      subject.add(1, "world")
      subject.add(2, "Iñtërnâtiônàlizætiøn")
    end

    it "returns a list of items with scores in given range" do
      subject.range(0, 1).should == ["hello", "world"]
    end

    it "is idempotent" do
      subject.range(0, 1).should == subject.range(0, 1)
    end

    it "allows for limits" do
      subject.range(0, 1, 1).should == ["hello"]
    end
  end

  describe "#range!" do
    before do
      subject.add(0, "hello")
      subject.add(1, "world")
      subject.add(2, "Iñtërnâtiônàlizætiøn")
    end

    it "removes items from heap after extraction" do
      subject.range!(0, 1).should == ["hello", "world"]
      subject.range!(0, 1).should == []
    end

    it "allows for limits" do
      subject.range!(0, 2, 2).should == ["hello", "world"]
      subject.range!(0, 2, 2).should == ["Iñtërnâtiônàlizætiøn"]
    end
  end

  describe "#count" do
    it "returns a number of elements in the heap" do
      subject.count.should == 0
      subject.add(0, "hello")
      subject.add(10, "world")
      subject.count.should == 2
    end
  end

  describe "#purge" do
    it "cleans the heap" do
      subject.add(0, "hello")
      subject.add(5, "world")
      subject.count.should == 2
      subject.purge
      subject.count.should == 0
    end
  end


  it "allows to store arbitrary objects" do
    point = Point.new(1.0, 2.0)
    subject.add(0, point)
    subject.range(0, 0).first.should == point
  end

  it "works with timestamps" do
    t = Time.now
    subject.add(t, {"hello" => "world"})
    subject.add(t-3, {"foo" => "bar"})
    subject.add(t+3, {"bar" => "baz"})
    subject.range(t-1, t+1).should == [{"hello" => "world"}]
    subject.range!(t-1, t+1).should == [{"hello" => "world"}]
  end
end


