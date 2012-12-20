require "spec_helper"

describe Sunspot::RedisIndexQueue::Client do
  TestPerson = Struct.new(:id, :first_name, :last_name)

  subject { described_class.new($session, $redis_config) }
  before(:each) { subject.heap.purge }
  describe "#count" do
    it "returns number of elements in the heap" do
      subject.count.should == 0
      subject.heap.add(0, "hello")
      subject.count.should == 1
    end
  end

  describe "#index" do
    it "adds an entry to the heap" do
      person = TestPerson.new(9, "mark", "abramov")
      subject.index(person)
      subject.count.should == 1
      indexed_entry = subject.heap.range(0, Time.now).first
      indexed_entry.should be_a(Sunspot::RedisIndexQueue::Client::Entry)
      indexed_entry.object_class_name.should == "TestPerson"
      indexed_entry.object_id.should == 9
      indexed_entry.run_at.should be_within(1.second).of(Time.now)
      indexed_entry.to_remove.should be_false
    end

    it "respects index_delay option" do
      person = TestPerson.new(9, "mark", "abramov")
      subject.options[:index_delay] = 20
      subject.index(person)
      subject.count.should == 1
      subject.get(0, Time.now).should be_blank
      subject.get(0, Time.now + 20).should_not be_blank
    end
  end

  describe "#remove" do
    it "adds an entry to the heap" do
      person = TestPerson.new(9, "mark", "abramov")
      subject.remove(person)
      subject.count.should == 1
      indexed_entry = subject.heap.range(0, Time.now).first
      indexed_entry.should be_a(Sunspot::RedisIndexQueue::Client::Entry)
      indexed_entry.object_class_name.should == "TestPerson"
      indexed_entry.object_id.should == 9
      indexed_entry.run_at.should be_within(1.second).of(Time.now)
      indexed_entry.to_remove.should be_true
    end

    it "respects index_delay option" do
      person = TestPerson.new(9, "mark", "abramov")
      subject.options[:index_delay] = 20
      subject.remove(person)
      subject.count.should == 1
      subject.get(0, Time.now).should be_blank
      subject.get(0, Time.now + 20).should_not be_blank
    end
  end

  describe "#get" do
    it "wraps around heap.range" do
      subject.index(TestPerson.new(999, "mark", "abramov"))
      subject.get(0, Time.now).first.object_id.should == 999
    end

    it "removes items from heap" do
      subject.index(TestPerson.new(999, "mark", "abramov"))
      subject.get(0, Time.now).count.should == 1
      subject.get(0, Time.now).count.should == 0
    end

    it "has a limit option" do
      subject.index(TestPerson.new(999, "mark", "abramov"))
      subject.index(TestPerson.new(1024, "joe", "smith"))
      subject.get(0, Time.now, 0).count.should == 0
      subject.get(0, Time.now, 1).count.should == 1
      subject.get(0, Time.now, 1).count.should == 1
      subject.get(0, Time.now, 1).count.should == 0
    end
  end

  describe "#process" do
    it "selects entries to index and calls _index with them" do
      entry = stub(:entry, :to_remove => false)
      subject.stub(:get).and_return([entry])
      subject.should_receive(:_index).with([entry])
      subject.should_not_receive(:_remove)
      subject.process
    end

    it "selects entries to remove and calls _remove with them" do
      entry = stub(:entry, :to_remove => true)
      subject.stub(:get).and_return([entry])
      subject.should_receive(:_remove).with([entry])
      subject.should_not_receive(:_index)
      subject.process
    end

    it "returns a number of items processed" do
      entry = stub(:entry, :to_remove => false)
      subject.stub(:get).and_return([entry])
      subject.stub(:process_entry).with(entry)
      subject.stub(:_index)
      subject.process.should == 1
    end
  end

  describe "#_index" do
    it "delegates to session" do
      entry = Sunspot::RedisIndexQueue::Client::Entry.new(:attempts_count => 0, :run_at => 3.days.ago)
      indexed_object = stub
      entry.stub(:object) { indexed_object }
      $session.should_receive(:index).with(indexed_object)
      subject._index([entry])
    end

    it "requeues on exceptions" do
      entry = Sunspot::RedisIndexQueue::Client::Entry.new(:attempts_count => 0, :run_at => 3.days.ago)
      $session.stub(:index) { raise Timeout::TimeoutError }
      subject.should_receive(:requeue).with([entry])
      subject._index([entry])
    end
  end

  describe "#_remove" do
    it "delegates to session" do
      entry = Sunspot::RedisIndexQueue::Client::Entry.new(:attempts_count => 0, :run_at => 3.days.ago)
      indexed_object = stub
      entry.stub(:object) { indexed_object }
      $session.should_receive(:remove).with(indexed_object)
      subject._remove([entry])
    end

    it "requeues on exceptions" do
      entry = Sunspot::RedisIndexQueue::Client::Entry.new(:attempts_count => 0, :run_at => 3.days.ago)
      $session.stub(:remove) { raise Timeout::TimeoutError }
      subject.should_receive(:requeue).with([entry])
      subject._remove([entry])
    end
  end
  describe "#requeue" do
    it "updates requeued entry run_at and attempts_count" do
      subject.should_receive(:add) do |entry|
        entry.attempts_count.should == 1
        entry.run_at.should >= Time.now
      end
      entry = Sunspot::RedisIndexQueue::Client::Entry.new(:attempts_count => 0, :run_at => 3.days.ago)
      subject.requeue(entry)
    end

    it "doesn't add entry to queue if its attempts are exceeded" do
      subject.should_not_receive(:add)
      entry = Sunspot::RedisIndexQueue::Client::Entry.new(:attempts_count => subject.max_attempts_count)
      subject.requeue(entry)
    end
  end
end
