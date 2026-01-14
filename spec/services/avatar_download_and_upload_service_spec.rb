# frozen_string_literal: true

require "rails_helper"

RSpec.describe AvatarDownloadAndUploadService do
  let(:storage) { instance_double(AvatarStorage::S3) }
  let(:service) { described_class.new(storage: storage) }

  let(:avatar_url) { "https://avatars.githubusercontent.com/u/178611968?v=4" }
  let(:expected_key) { "avatars/178611968" }
  let(:image_data) { "\x89PNG\r\n\x1a\n" } # PNG magic bytes
  let(:content_type) { "image/png" }

  describe "#call" do
    context "when avatar already exists in storage" do
      before do
        allow(storage).to receive(:exists?).with(key: expected_key).and_return(true)
      end

      it "skips upload and returns skipped result" do
        result = service.call(avatar_url: avatar_url)

        expect(result).to eq({ key: expected_key, uploaded: false, skipped: true })
      end

      it "does not download the avatar" do
        service.call(avatar_url: avatar_url)

        expect(a_request(:get, avatar_url)).not_to have_been_made
      end

      it "does not call upload" do
        allow(storage).to receive(:upload)

        service.call(avatar_url: avatar_url)

        expect(storage).not_to have_received(:upload)
      end
    end

    context "when avatar does not exist in storage" do
      before do
        allow(storage).to receive(:exists?).with(key: expected_key).and_return(false)
        allow(storage).to receive(:upload).and_return(true)

        stub_request(:get, avatar_url)
          .to_return(
            status: 200,
            body: image_data,
            headers: { "Content-Type" => content_type }
          )
      end

      it "downloads and uploads the avatar" do
        result = service.call(avatar_url: avatar_url)

        expect(result).to eq({ key: expected_key, uploaded: true, skipped: false })
      end

      it "downloads from the avatar URL" do
        service.call(avatar_url: avatar_url)

        expect(a_request(:get, avatar_url)).to have_been_made.once
      end

      it "uploads with correct parameters" do
        service.call(avatar_url: avatar_url)

        expect(storage).to have_received(:upload).with(
          key: expected_key,
          body: image_data,
          content_type: content_type
        )
      end
    end

    context "when avatar URL uses different content types" do
      before do
        allow(storage).to receive(:exists?).and_return(false)
        allow(storage).to receive(:upload).and_return(true)
      end

      %w[image/jpeg image/png image/gif image/webp].each do |type|
        it "handles #{type} content type" do
          stub_request(:get, avatar_url)
            .to_return(
              status: 200,
              body: image_data,
              headers: { "Content-Type" => type }
            )

          service.call(avatar_url: avatar_url)

          expect(storage).to have_received(:upload).with(
            key: expected_key,
            body: image_data,
            content_type: type
          )
        end
      end

      it "handles content type with charset" do
        stub_request(:get, avatar_url)
          .to_return(
            status: 200,
            body: image_data,
            headers: { "Content-Type" => "image/png; charset=utf-8" }
          )

        service.call(avatar_url: avatar_url)

        expect(storage).to have_received(:upload).with(
          key: expected_key,
          body: image_data,
          content_type: "image/png"
        )
      end

      it "defaults to image/png when content type is missing" do
        stub_request(:get, avatar_url)
          .to_return(status: 200, body: image_data)

        service.call(avatar_url: avatar_url)

        expect(storage).to have_received(:upload).with(
          key: expected_key,
          body: image_data,
          content_type: "image/png"
        )
      end
    end

    context "when GitHub redirects the avatar URL" do
      let(:redirect_url) { "https://avatars.githubusercontent.com/u/178611968?v=5" }

      before do
        allow(storage).to receive(:exists?).and_return(false)
        allow(storage).to receive(:upload).and_return(true)

        stub_request(:get, avatar_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })

        stub_request(:get, redirect_url)
          .to_return(
            status: 200,
            body: image_data,
            headers: { "Content-Type" => content_type }
          )
      end

      it "follows the redirect" do
        service.call(avatar_url: avatar_url)

        expect(a_request(:get, avatar_url)).to have_been_made.once
        expect(a_request(:get, redirect_url)).to have_been_made.once
      end

      it "uploads the final image" do
        service.call(avatar_url: avatar_url)

        expect(storage).to have_received(:upload).with(
          key: expected_key,
          body: image_data,
          content_type: content_type
        )
      end
    end

    context "when URL is invalid" do
      it "raises InvalidUrlError for non-HTTP URLs" do
        expect {
          service.call(avatar_url: "ftp://example.com/avatar.png")
        }.to raise_error(AvatarDownloadAndUploadService::InvalidUrlError, /Invalid URL scheme/)
      end

      it "raises InvalidUrlError for non-GitHub URLs" do
        expect {
          service.call(avatar_url: "https://example.com/avatar.png")
        }.to raise_error(AvatarDownloadAndUploadService::InvalidUrlError, /Not a GitHub avatar URL/)
      end

      it "raises InvalidUrlError for malformed URLs" do
        expect {
          service.call(avatar_url: "not-a-url")
        }.to raise_error(AvatarDownloadAndUploadService::InvalidUrlError)
      end

      it "raises InvalidUrlError when user ID cannot be extracted" do
        expect {
          service.call(avatar_url: "https://avatars.githubusercontent.com/some/other/path")
        }.to raise_error(AvatarDownloadAndUploadService::InvalidUrlError, /Cannot extract user ID/)
      end
    end

    context "when download fails" do
      before do
        allow(storage).to receive(:exists?).and_return(false)
      end

      it "raises DownloadError on HTTP error response" do
        stub_request(:get, avatar_url).to_return(status: 404)

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndUploadService::DownloadError, /404/)
      end

      it "raises DownloadError on server error" do
        stub_request(:get, avatar_url).to_return(status: 500)

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndUploadService::DownloadError, /500/)
      end

      it "raises DownloadError on network timeout" do
        stub_request(:get, avatar_url).to_timeout

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndUploadService::DownloadError, /Network error/)
      end

      it "raises DownloadError on connection refused" do
        stub_request(:get, avatar_url).to_raise(Errno::ECONNREFUSED)

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndUploadService::DownloadError, /Network error/)
      end
    end

    context "key derivation" do
      before do
        allow(storage).to receive(:exists?).and_return(true)
      end

      it "extracts user ID from standard avatar URL" do
        result = service.call(avatar_url: "https://avatars.githubusercontent.com/u/12345?v=4")

        expect(result[:key]).to eq("avatars/12345")
      end

      it "extracts user ID without query parameters" do
        result = service.call(avatar_url: "https://avatars.githubusercontent.com/u/67890")

        expect(result[:key]).to eq("avatars/67890")
      end

      it "handles large user IDs" do
        result = service.call(avatar_url: "https://avatars.githubusercontent.com/u/999999999999")

        expect(result[:key]).to eq("avatars/999999999999")
      end
    end
  end
end
