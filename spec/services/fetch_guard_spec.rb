require "rails_helper"

RSpec.describe FetchGuard do
  let(:guard) { described_class.new }

  describe "#should_fetch?" do
    context "when record is nil" do
      it "returns true (fetch needed)" do
        expect(guard.should_fetch?(record: nil)).to be true
      end
    end

    context "when record was recently updated" do
      let(:record) { create(:github_user, updated_at: 2.minutes.ago) }

      it "returns false (fetch not needed)" do
        expect(guard.should_fetch?(record: record)).to be false
      end
    end

    context "when record is older than threshold" do
      let(:record) { create(:github_user, updated_at: 10.minutes.ago) }

      it "returns true (fetch needed)" do
        expect(guard.should_fetch?(record: record)).to be true
      end
    end

    context "when staleness threshold is set to 0" do
      let(:record) { create(:github_user, updated_at: 1.minute.ago) }

      around do |example|
        original_value = ENV["STALENESS_THRESHOLD_MINUTES"]
        ENV["STALENESS_THRESHOLD_MINUTES"] = "0"
        example.run
        ENV["STALENESS_THRESHOLD_MINUTES"] = original_value
      end

      it "returns true even if record was just updated (always fetch)" do
        new_guard = described_class.new
        expect(new_guard.should_fetch?(record: record)).to be true
      end
    end

    context "when staleness threshold is overridden in constructor" do
      let(:guard) { described_class.new(staleness_threshold_minutes: 10) }
      let(:fresh_record) { create(:github_user, updated_at: 5.minutes.ago) }
      let(:stale_record) { create(:github_user, updated_at: 15.minutes.ago) }

      it "uses the custom threshold" do
        expect(guard.should_fetch?(record: fresh_record)).to be false
        expect(guard.should_fetch?(record: stale_record)).to be true
      end
    end
  end
end
