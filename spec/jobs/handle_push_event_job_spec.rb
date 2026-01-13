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
end
