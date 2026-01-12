require "rails_helper"

RSpec.describe SavePushEventJob, type: :job do
  let(:event_data) do
    {
      "id" => "7401144939",
      "payload" => { "repository_id" => 1113957516 }
    }
  end

  describe "#perform" do
    it "calls PushEventSaver with event data" do
      saver = instance_double(PushEventSaver)
      allow(PushEventSaver).to receive(:new).and_return(saver)
      allow(saver).to receive(:call).with(event_data: event_data)

      described_class.new.perform(event_data)

      expect(saver).to have_received(:call).with(event_data: event_data)
    end
  end
end
