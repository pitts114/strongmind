RSpec.shared_examples "a fetch guard" do |model_factory:, identifier_attribute:, identifier_value:|
  let(:guard) { described_class.new }

  describe "#find_unless_fetch_needed" do
    context "when record does not exist" do
      it "returns nil (fetch needed)" do
        expect(guard.find_unless_fetch_needed(identifier: identifier_value)).to be_nil
      end
    end

    context "when record exists and was recently updated" do
      let!(:record) do
        create(model_factory, identifier_attribute => identifier_value, updated_at: 2.minutes.ago)
      end

      it "returns the record (fetch not needed)" do
        expect(guard.find_unless_fetch_needed(identifier: identifier_value)).to eq(record)
      end
    end

    context "when record exists but is older than threshold" do
      let!(:record) do
        create(model_factory, identifier_attribute => identifier_value, updated_at: 10.minutes.ago)
      end

      it "returns nil (fetch needed)" do
        expect(guard.find_unless_fetch_needed(identifier: identifier_value)).to be_nil
      end
    end

    context "when staleness threshold is set to 0" do
      let!(:record) do
        create(model_factory, identifier_attribute => identifier_value, updated_at: 1.minute.ago)
      end

      around do |example|
        original_value = ENV["STALENESS_THRESHOLD_MINUTES"]
        ENV["STALENESS_THRESHOLD_MINUTES"] = "0"
        example.run
        ENV["STALENESS_THRESHOLD_MINUTES"] = original_value
      end

      it "returns nil even if record was just updated (always fetch)" do
        new_guard = described_class.new
        expect(new_guard.find_unless_fetch_needed(identifier: identifier_value)).to be_nil
      end
    end
  end
end
