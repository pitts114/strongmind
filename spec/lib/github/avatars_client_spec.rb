# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"
require "github/avatars_client"

RSpec.describe Github::AvatarsClient do
  let(:client) { described_class.new }
  let(:avatar_url) { "https://avatars.githubusercontent.com/u/178611968?v=4" }
  let(:image_data) { "\x89PNG\r\n\x1a\n" } # PNG magic bytes
  let(:content_type) { "image/png" }

  describe "#download" do
    context "when download succeeds" do
      before do
        stub_request(:get, avatar_url)
          .to_return(
            status: 200,
            body: image_data,
            headers: { "Content-Type" => content_type }
          )
      end

      it "returns a hash with temp_file and content_type" do
        result = client.download(url: avatar_url)

        expect(result).to have_key(:temp_file)
        expect(result).to have_key(:content_type)
        expect(result[:content_type]).to eq(content_type)
      end

      it "returns a Tempfile with the image data" do
        result = client.download(url: avatar_url)

        expect(result[:temp_file]).to be_a(Tempfile)
        expect(result[:temp_file].read).to eq(image_data.b)
      end

      it "extracts content type from response header" do
        result = client.download(url: avatar_url)

        expect(result[:content_type]).to eq("image/png")
      end

      it "strips charset from content type" do
        stub_request(:get, avatar_url)
          .to_return(
            status: 200,
            body: image_data,
            headers: { "Content-Type" => "image/png; charset=utf-8" }
          )

        result = client.download(url: avatar_url)

        expect(result[:content_type]).to eq("image/png")
      end

      it "defaults to image/png when content type is missing" do
        stub_request(:get, avatar_url)
          .to_return(status: 200, body: image_data)

        result = client.download(url: avatar_url)

        expect(result[:content_type]).to eq("image/png")
      end
    end

    context "when server redirects" do
      let(:redirect_url) { "https://avatars.githubusercontent.com/u/178611968?v=5" }

      before do
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
        result = client.download(url: avatar_url)

        expect(a_request(:get, avatar_url)).to have_been_made.once
        expect(a_request(:get, redirect_url)).to have_been_made.once
        expect(result[:temp_file].read).to eq(image_data.b)
      end
    end

    context "when too many redirects" do
      before do
        # Create a redirect loop
        stub_request(:get, avatar_url)
          .to_return(status: 302, headers: { "Location" => avatar_url })
      end

      it "raises DownloadError" do
        expect {
          client.download(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::DownloadError, /Too many redirects/)
      end
    end

    context "when HTTP error occurs" do
      it "raises DownloadError on 404" do
        stub_request(:get, avatar_url).to_return(status: 404)

        expect {
          client.download(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::DownloadError, /404/)
      end

      it "raises DownloadError on 500" do
        stub_request(:get, avatar_url).to_return(status: 500)

        expect {
          client.download(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::DownloadError, /500/)
      end
    end

    context "when network error occurs" do
      it "raises DownloadError on timeout" do
        stub_request(:get, avatar_url).to_timeout

        expect {
          client.download(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::DownloadError, /Network error/)
      end

      it "raises DownloadError on connection refused" do
        stub_request(:get, avatar_url).to_raise(Errno::ECONNREFUSED)

        expect {
          client.download(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::DownloadError, /Network error/)
      end
    end

    context "file size limits" do
      context "when Content-Length header exceeds limit" do
        it "raises FileTooLargeError" do
          stub_request(:get, avatar_url)
            .to_return(
              status: 200,
              headers: { "Content-Length" => "15000000" } # 15 MB
            )

          expect {
            client.download(url: avatar_url)
          }.to raise_error(
            Github::AvatarsClient::FileTooLargeError,
            /exceeds maximum/
          )
        end
      end

      context "when streamed bytes exceed limit" do
        let(:large_body) { "x" * (11 * 1024 * 1024) } # 11 MB

        it "raises FileTooLargeError during streaming" do
          stub_request(:get, avatar_url)
            .to_return(status: 200, body: large_body)

          expect {
            client.download(url: avatar_url)
          }.to raise_error(
            Github::AvatarsClient::FileTooLargeError,
            /exceeded maximum.*during download/
          )
        end
      end

      context "with custom max_file_size" do
        let(:small_limit_client) { described_class.new(max_file_size: 100) }

        it "respects custom limit" do
          stub_request(:get, avatar_url)
            .to_return(
              status: 200,
              body: "x" * 200,
              headers: { "Content-Type" => "image/png" }
            )

          expect {
            small_limit_client.download(url: avatar_url)
          }.to raise_error(Github::AvatarsClient::FileTooLargeError)
        end
      end
    end

    context "temp file cleanup" do
      it "cleans up temp file on HTTP error" do
        stub_request(:get, avatar_url).to_return(status: 500)

        temp_files = []
        allow(Tempfile).to receive(:new).and_wrap_original do |method, *args, **kwargs|
          tf = method.call(*args, **kwargs)
          temp_files << tf
          tf
        end

        expect {
          client.download(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::DownloadError)

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
          client.download(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::FileTooLargeError)

        temp_files.each do |tf|
          expect(tf.closed?).to be true
        end
      end

      it "cleans up temp files when following redirects" do
        redirect_url = "https://avatars.githubusercontent.com/u/178611968?v=5"

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

        result = client.download(url: avatar_url)

        # First temp file (from redirect) should be cleaned up
        # Second temp file (final) should be open and returned
        expect(temp_files.size).to eq(2)
        expect(temp_files.first.closed?).to be true
        expect(temp_files.last).to eq(result[:temp_file])
      end
    end
  end

  describe "configuration" do
    it "uses default timeout of 30 seconds" do
      expect(client.timeout).to eq(30)
    end

    it "uses default max file size of 10 MB" do
      expect(client.max_file_size).to eq(10 * 1024 * 1024)
    end

    it "accepts custom timeout" do
      custom_client = described_class.new(timeout: 60)
      expect(custom_client.timeout).to eq(60)
    end

    it "accepts custom max file size" do
      custom_client = described_class.new(max_file_size: 5 * 1024 * 1024)
      expect(custom_client.max_file_size).to eq(5 * 1024 * 1024)
    end
  end
end
