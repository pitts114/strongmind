require "rails_helper"

RSpec.describe HandlePushEventJob, type: :job do
  let(:event_data) do
    {
      "id" => "7401144939",
      "payload" => { "repository_id" => 1113957516 }
    }
  end

  describe "#perform" do
    it "calls PushEventHandler with event data" do
      handler = instance_double(PushEventHandler)
      allow(PushEventHandler).to receive(:new).and_return(handler)
      allow(handler).to receive(:call).with(event_data: event_data)

      described_class.new.perform(event_data)

      expect(handler).to have_received(:call).with(event_data: event_data)
    end
  end

  describe "failure logging" do
    before do
      allow(Rails.logger).to receive(:error)
    end

    describe "on ActiveRecord::Deadlocked after max retries" do
      it "logs when all retries exhausted" do
        handler = instance_double(PushEventHandler)
        allow(PushEventHandler).to receive(:new).and_return(handler)
        allow(handler).to receive(:call).and_raise(ActiveRecord::Deadlocked.new("Deadlock found"))

        job = described_class.new(event_data)
        # Set exception_executions to simulate max retries reached (attempts: 3)
        job.exception_executions["[ActiveRecord::Deadlocked]"] = 3

        job.perform_now

        expect(Rails.logger).to have_received(:error).with(
          "HandlePushEventJob: Failed after max retries (deadlock) - event_id: 7401144939, error: Deadlock found"
        )
      end
    end

    describe "on ActiveRecord::ConnectionNotEstablished after max retries" do
      it "logs when all retries exhausted" do
        handler = instance_double(PushEventHandler)
        allow(PushEventHandler).to receive(:new).and_return(handler)
        allow(handler).to receive(:call).and_raise(ActiveRecord::ConnectionNotEstablished.new("Connection failed"))

        job = described_class.new(event_data)
        # Set exception_executions to simulate max retries reached (attempts: 3)
        job.exception_executions["[ActiveRecord::ConnectionNotEstablished]"] = 3

        job.perform_now

        expect(Rails.logger).to have_received(:error).with(
          "HandlePushEventJob: Failed after max retries (connection error) - event_id: 7401144939, error: Connection failed"
        )
      end
    end
  end
end
