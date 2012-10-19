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

  describe "#process_entry" do
    context "when indexed" do
      let(:person) { TestPerson.new(9, "mark", "abramov") }
      let(:entry) { subject.new_entry_for_object(person) }

      it "delegates indexing to wrapped session" do
        TestPerson.stub(:find).with(person.id).and_return(person)
        $session.should_receive(:index).with(person)
        subject.process_entry(entry)
      end
    end


    context "when removed" do
      let(:person) { TestPerson.new(9, "mark", "abramov") }
      let(:entry) { subject.new_entry_for_object(person, :to_remove => true) }

      it "delegates removing to wrapped session" do
        $session.should_receive(:remove_by_id).with(person.class.name, person.id)
        subject.process_entry(entry)
      end
    end

    context "when failed" do
      let(:person) { TestPerson.new(9, "mark", "abramov") }
      let(:entry) { subject.new_entry_for_object(person) }

      it "reenqueues the entry" do
        $session.stub!(:index) { raise Timeout::Error, "timed out" }
        subject.process_entry(entry)
        subject.get(Time.now, Time.now + subject.retry_interval).should_not be_blank
      end
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
    it "extracts items from the queue and calls #process_entry on them" do
      entry = stub(:entry)
      subject.stub(:get).and_return([entry])
      subject.should_receive(:process_entry).with(entry)
      subject.process
    end

    it "returns a number of items processed" do
      entry = stub(:entry)
      subject.stub(:get).and_return([entry])
      subject.stub(:process_entry).with(entry)
      subject.process.should == 1
    end
  end
end
