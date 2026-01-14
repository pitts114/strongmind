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

        expect(storage).to have_received(:upload) do |args|
          expect(args[:key]).to eq(expected_key)
          expect(args[:content_type]).to eq(content_type)
          expect(args[:body]).to be_a(Tempfile)
          expect(args[:body].read).to eq(image_data)
        end
      end

      it "passes a Tempfile to storage.upload" do
        service.call(avatar_url: avatar_url)

        expect(storage).to have_received(:upload) do |args|
          expect(args[:body]).to respond_to(:read)
          expect(args[:body]).to be_a(Tempfile)
        end
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

          expect(storage).to have_received(:upload) do |args|
            expect(args[:key]).to eq(expected_key)
            expect(args[:content_type]).to eq(type)
            expect(args[:body].read).to eq(image_data)
          end
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

        expect(storage).to have_received(:upload) do |args|
          expect(args[:key]).to eq(expected_key)
          expect(args[:content_type]).to eq("image/png")
          expect(args[:body].read).to eq(image_data)
        end
      end

      it "defaults to image/png when content type is missing" do
        stub_request(:get, avatar_url)
          .to_return(status: 200, body: image_data)

        service.call(avatar_url: avatar_url)

        expect(storage).to have_received(:upload) do |args|
          expect(args[:key]).to eq(expected_key)
          expect(args[:content_type]).to eq("image/png")
          expect(args[:body].read).to eq(image_data)
        end
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

        expect(storage).to have_received(:upload) do |args|
          expect(args[:key]).to eq(expected_key)
          expect(args[:content_type]).to eq(content_type)
          expect(args[:body].read).to eq(image_data)
        end
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

    context "file size limits" do
      before do
        allow(storage).to receive(:exists?).and_return(false)
      end

      context "when Content-Length header exceeds limit" do
        it "raises FileTooLargeError without downloading body" do
          stub_request(:get, avatar_url)
            .to_return(
              status: 200,
              headers: { "Content-Length" => "15000000" } # 15 MB
            )

          expect {
            service.call(avatar_url: avatar_url)
          }.to raise_error(
            AvatarDownloadAndUploadService::FileTooLargeError,
            /exceeds maximum/
          )
        end
      end

      context "when streamed bytes exceed limit (no Content-Length)" do
        let(:large_body) { "x" * (11 * 1024 * 1024) } # 11 MB

        it "raises FileTooLargeError during streaming" do
          stub_request(:get, avatar_url)
            .to_return(status: 200, body: large_body)

          expect {
            service.call(avatar_url: avatar_url)
          }.to raise_error(
            AvatarDownloadAndUploadService::FileTooLargeError,
            /exceeded maximum.*during download/
          )
        end
      end

      context "when file is within limits" do
        it "downloads and uploads successfully" do
          allow(storage).to receive(:upload).and_return(true)

          stub_request(:get, avatar_url)
            .to_return(
              status: 200,
              body: image_data,
              headers: {
                "Content-Type" => content_type,
                "Content-Length" => image_data.bytesize.to_s
              }
            )

          result = service.call(avatar_url: avatar_url)

          expect(result[:uploaded]).to be true
        end
      end

      context "with custom max_file_size" do
        let(:small_limit_service) do
          described_class.new(storage: storage, max_file_size: 100)
        end

        it "respects custom limit" do
          stub_request(:get, avatar_url)
            .to_return(
              status: 200,
              body: "x" * 200,
              headers: { "Content-Type" => "image/png" }
            )

          expect {
            small_limit_service.call(avatar_url: avatar_url)
          }.to raise_error(AvatarDownloadAndUploadService::FileTooLargeError)
        end
      end
    end

    context "temp file handling" do
      before do
        allow(storage).to receive(:exists?).and_return(false)
      end

      it "cleans up temp file after successful upload" do
        allow(storage).to receive(:upload).and_return(true)

        stub_request(:get, avatar_url)
          .to_return(status: 200, body: image_data, headers: { "Content-Type" => content_type })

        temp_files = []
        allow(Tempfile).to receive(:new).and_wrap_original do |method, *args, **kwargs|
          tf = method.call(*args, **kwargs)
          temp_files << tf
          tf
        end

        service.call(avatar_url: avatar_url)

        temp_files.each do |tf|
          expect(tf.closed?).to be true
        end
      end

      it "cleans up temp file on download error" do
        stub_request(:get, avatar_url).to_return(status: 500)

        temp_files = []
        allow(Tempfile).to receive(:new).and_wrap_original do |method, *args, **kwargs|
          tf = method.call(*args, **kwargs)
          temp_files << tf
          tf
        end

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndUploadService::DownloadError)

        temp_files.each do |tf|
          expect(tf.closed?).to be true
        end
      end

      it "cleans up temp file on size limit exceeded" do
        stub_request(:get, avatar_url)
          .to_return(
            status: 200,
            headers: { "Content-Length" => "999999999" }
          )

        temp_files = []
        allow(Tempfile).to receive(:new).and_wrap_original do |method, *args, **kwargs|
          tf = method.call(*args, **kwargs)
          temp_files << tf
          tf
        end

        expect {
          service.call(avatar_url: avatar_url)
        }.to raise_error(AvatarDownloadAndUploadService::FileTooLargeError)

        temp_files.each do |tf|
          expect(tf.closed?).to be true
        end
      end
    end

    context "redirect handling with temp files" do
      let(:redirect_url) { "https://avatars.githubusercontent.com/u/178611968?v=5" }

      before do
        allow(storage).to receive(:exists?).and_return(false)
        allow(storage).to receive(:upload).and_return(true)
      end

      it "cleans up temp file from initial request when following redirect" do
        stub_request(:get, avatar_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })

        stub_request(:get, redirect_url)
          .to_return(status: 200, body: image_data, headers: { "Content-Type" => content_type })

        temp_files = []
        allow(Tempfile).to receive(:new).and_wrap_original do |method, *args, **kwargs|
          tf = method.call(*args, **kwargs)
          temp_files << tf
          tf
        end

        service.call(avatar_url: avatar_url)

        # All temp files should be cleaned up
        temp_files.each do |tf|
          expect(tf.closed?).to be true
        end
      end
    end
  end
end
