# frozen_string_literal: true

require "rails_helper"

RSpec.describe AvatarKeyDeriver do
  let(:deriver) { described_class.new }

  describe "#call" do
    context "with valid GitHub avatar URLs" do
      it "includes version in key when v param is present" do
        result = deriver.call(url: "https://avatars.githubusercontent.com/u/178611968?v=4")

        expect(result).to eq("avatars/178611968-4")
      end

      it "excludes version suffix when v param is absent" do
        result = deriver.call(url: "https://avatars.githubusercontent.com/u/67890")

        expect(result).to eq("avatars/67890")
      end

      it "handles different version numbers" do
        result = deriver.call(url: "https://avatars.githubusercontent.com/u/12345?v=10")

        expect(result).to eq("avatars/12345-10")
      end

      it "handles large user IDs with version" do
        result = deriver.call(url: "https://avatars.githubusercontent.com/u/999999999999?v=1")

        expect(result).to eq("avatars/999999999999-1")
      end

      it "handles large user IDs without version" do
        result = deriver.call(url: "https://avatars.githubusercontent.com/u/999999999999")

        expect(result).to eq("avatars/999999999999")
      end

      it "accepts githubusercontent.com without avatars subdomain" do
        result = deriver.call(url: "https://githubusercontent.com/u/12345?v=2")

        expect(result).to eq("avatars/12345-2")
      end

      it "accepts HTTP URLs" do
        result = deriver.call(url: "http://avatars.githubusercontent.com/u/12345?v=3")

        expect(result).to eq("avatars/12345-3")
      end

      it "handles bot/app avatar URLs with /in/ path" do
        result = deriver.call(url: "https://avatars.githubusercontent.com/in/15368?v=4")

        expect(result).to eq("avatars/in-15368-4")
      end

      it "handles bot/app avatar URLs without version" do
        result = deriver.call(url: "https://avatars.githubusercontent.com/in/15368")

        expect(result).to eq("avatars/in-15368")
      end

      it "ignores other query parameters" do
        result = deriver.call(url: "https://avatars.githubusercontent.com/u/12345?s=200&v=4")

        expect(result).to eq("avatars/12345-4")
      end
    end

    context "with invalid URL schemes" do
      it "raises InvalidUrlError for FTP URLs" do
        expect {
          deriver.call(url: "ftp://avatars.githubusercontent.com/u/12345")
        }.to raise_error(AvatarKeyDeriver::InvalidUrlError, /Invalid URL scheme/)
      end

      it "raises InvalidUrlError for file URLs" do
        expect {
          deriver.call(url: "file:///etc/passwd")
        }.to raise_error(AvatarKeyDeriver::InvalidUrlError, /Invalid URL scheme/)
      end
    end

    context "with invalid hosts" do
      it "raises InvalidUrlError for non-GitHub hosts" do
        expect {
          deriver.call(url: "https://example.com/u/12345")
        }.to raise_error(AvatarKeyDeriver::InvalidUrlError, /Not a GitHub avatar URL/)
      end

      it "raises InvalidUrlError for similar-looking hosts" do
        expect {
          deriver.call(url: "https://fake-githubusercontent.com/u/12345")
        }.to raise_error(AvatarKeyDeriver::InvalidUrlError, /Not a GitHub avatar URL/)
      end

      it "raises InvalidUrlError for api.github.com" do
        expect {
          deriver.call(url: "https://api.github.com/users/octocat")
        }.to raise_error(AvatarKeyDeriver::InvalidUrlError, /Not a GitHub avatar URL/)
      end
    end

    context "with invalid paths" do
      it "raises InvalidUrlError when path doesn't match pattern" do
        expect {
          deriver.call(url: "https://avatars.githubusercontent.com/some/other/path")
        }.to raise_error(AvatarKeyDeriver::InvalidUrlError, /Cannot extract ID/)
      end

      it "raises InvalidUrlError for non-numeric user IDs" do
        expect {
          deriver.call(url: "https://avatars.githubusercontent.com/u/octocat")
        }.to raise_error(AvatarKeyDeriver::InvalidUrlError, /Cannot extract ID/)
      end

      it "raises InvalidUrlError for empty path" do
        expect {
          deriver.call(url: "https://avatars.githubusercontent.com/")
        }.to raise_error(AvatarKeyDeriver::InvalidUrlError, /Cannot extract ID/)
      end
    end

    context "with malformed URLs" do
      it "raises InvalidUrlError for completely invalid URLs" do
        expect {
          deriver.call(url: "not-a-url")
        }.to raise_error(AvatarKeyDeriver::InvalidUrlError)
      end

      it "raises InvalidUrlError for empty string" do
        expect {
          deriver.call(url: "")
        }.to raise_error(AvatarKeyDeriver::InvalidUrlError)
      end
    end
  end
end
