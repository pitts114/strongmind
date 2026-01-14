# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"
require "github/avatars_client"
require "stringio"

RSpec.describe Github::AvatarsClient do
  let(:client) { described_class.new }
  let(:avatar_url) { "https://avatars.githubusercontent.com/u/178611968?v=4" }
  let(:image_data) { "\x89PNG\r\n\x1a\n" } # PNG magic bytes
  let(:content_type) { "image/png" }

  describe "#head" do
    context "when request succeeds" do
      before do
        stub_request(:head, avatar_url)
          .to_return(
            status: 200,
            headers: { "Content-Type" => content_type, "Content-Length" => "12345" }
          )
      end

      it "returns content_length and content_type" do
        result = client.head(url: avatar_url)

        expect(result[:content_length]).to eq(12345)
        expect(result[:content_type]).to eq(content_type)
      end

      it "handles missing content length" do
        stub_request(:head, avatar_url)
          .to_return(status: 200, headers: { "Content-Type" => content_type })

        result = client.head(url: avatar_url)

        expect(result[:content_length]).to be_nil
      end

      it "strips charset from content type" do
        stub_request(:head, avatar_url)
          .to_return(
            status: 200,
            headers: { "Content-Type" => "image/png; charset=utf-8" }
          )

        result = client.head(url: avatar_url)

        expect(result[:content_type]).to eq("image/png")
      end

      it "defaults to image/png when content type is missing" do
        stub_request(:head, avatar_url)
          .to_return(status: 200)

        result = client.head(url: avatar_url)

        expect(result[:content_type]).to eq("image/png")
      end
    end

    context "when server redirects" do
      let(:redirect_url) { "https://avatars.githubusercontent.com/u/178611968?v=5" }

      before do
        stub_request(:head, avatar_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })

        stub_request(:head, redirect_url)
          .to_return(
            status: 200,
            headers: { "Content-Type" => content_type, "Content-Length" => "5000" }
          )
      end

      it "follows the redirect" do
        result = client.head(url: avatar_url)

        expect(a_request(:head, avatar_url)).to have_been_made.once
        expect(a_request(:head, redirect_url)).to have_been_made.once
        expect(result[:content_length]).to eq(5000)
      end
    end

    context "when too many redirects" do
      before do
        stub_request(:head, avatar_url)
          .to_return(status: 302, headers: { "Location" => avatar_url })
      end

      it "raises DownloadError" do
        expect {
          client.head(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::DownloadError, /Too many redirects/)
      end
    end

    context "when HTTP error occurs" do
      it "raises DownloadError on 404" do
        stub_request(:head, avatar_url).to_return(status: 404)

        expect {
          client.head(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::DownloadError, /404/)
      end

      it "raises DownloadError on 500" do
        stub_request(:head, avatar_url).to_return(status: 500)

        expect {
          client.head(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::DownloadError, /500/)
      end
    end

    context "when network error occurs" do
      it "raises DownloadError on timeout" do
        stub_request(:head, avatar_url).to_timeout

        expect {
          client.head(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::DownloadError, /Network error/)
      end

      it "raises DownloadError on connection refused" do
        stub_request(:head, avatar_url).to_raise(Errno::ECONNREFUSED)

        expect {
          client.head(url: avatar_url)
        }.to raise_error(Github::AvatarsClient::DownloadError, /Network error/)
      end
    end
  end

  describe "#download" do
    let(:io) { StringIO.new.tap { |s| s.set_encoding(Encoding::ASCII_8BIT) } }

    context "when download succeeds" do
      before do
        stub_request(:get, avatar_url)
          .to_return(
            status: 200,
            body: image_data,
            headers: { "Content-Type" => content_type }
          )
      end

      it "returns bytes_written and content_type" do
        result = client.download(url: avatar_url, io: io)

        expect(result).to have_key(:bytes_written)
        expect(result).to have_key(:content_type)
        expect(result[:content_type]).to eq(content_type)
      end

      it "writes image data to the provided IO" do
        client.download(url: avatar_url, io: io)

        io.rewind
        expect(io.read).to eq(image_data.b)
      end

      it "returns correct bytes_written count" do
        result = client.download(url: avatar_url, io: io)

        expect(result[:bytes_written]).to eq(image_data.bytesize)
      end

      it "extracts content type from response header" do
        result = client.download(url: avatar_url, io: io)

        expect(result[:content_type]).to eq("image/png")
      end

      it "strips charset from content type" do
        stub_request(:get, avatar_url)
          .to_return(
            status: 200,
            body: image_data,
            headers: { "Content-Type" => "image/png; charset=utf-8" }
          )

        result = client.download(url: avatar_url, io: io)

        expect(result[:content_type]).to eq("image/png")
      end

      it "defaults to image/png when content type is missing" do
        stub_request(:get, avatar_url)
          .to_return(status: 200, body: image_data)

        result = client.download(url: avatar_url, io: io)

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

      it "follows the redirect and writes to IO" do
        client.download(url: avatar_url, io: io)

        expect(a_request(:get, avatar_url)).to have_been_made.once
        expect(a_request(:get, redirect_url)).to have_been_made.once
        io.rewind
        expect(io.read).to eq(image_data.b)
      end
    end

    context "when too many redirects" do
      before do
        stub_request(:get, avatar_url)
          .to_return(status: 302, headers: { "Location" => avatar_url })
      end

      it "raises DownloadError" do
        expect {
          client.download(url: avatar_url, io: io)
        }.to raise_error(Github::AvatarsClient::DownloadError, /Too many redirects/)
      end
    end

    context "when HTTP error occurs" do
      it "raises DownloadError on 404" do
        stub_request(:get, avatar_url).to_return(status: 404)

        expect {
          client.download(url: avatar_url, io: io)
        }.to raise_error(Github::AvatarsClient::DownloadError, /404/)
      end

      it "raises DownloadError on 500" do
        stub_request(:get, avatar_url).to_return(status: 500)

        expect {
          client.download(url: avatar_url, io: io)
        }.to raise_error(Github::AvatarsClient::DownloadError, /500/)
      end
    end

    context "when network error occurs" do
      it "raises DownloadError on timeout" do
        stub_request(:get, avatar_url).to_timeout

        expect {
          client.download(url: avatar_url, io: io)
        }.to raise_error(Github::AvatarsClient::DownloadError, /Network error/)
      end

      it "raises DownloadError on connection refused" do
        stub_request(:get, avatar_url).to_raise(Errno::ECONNREFUSED)

        expect {
          client.download(url: avatar_url, io: io)
        }.to raise_error(Github::AvatarsClient::DownloadError, /Network error/)
      end
    end

    context "file size limits with max_size parameter" do
      context "when streamed bytes exceed max_size" do
        let(:large_body) { "x" * 200 }

        it "raises FileSizeExceededError during streaming" do
          stub_request(:get, avatar_url)
            .to_return(status: 200, body: large_body)

          expect {
            client.download(url: avatar_url, io: io, max_size: 100)
          }.to raise_error(
            Github::AvatarsClient::FileSizeExceededError,
            /exceeded maximum.*during download/
          )
        end
      end

      context "when max_size is not provided" do
        let(:large_body) { "x" * 1000 }

        it "does not enforce any size limit" do
          stub_request(:get, avatar_url)
            .to_return(status: 200, body: large_body, headers: { "Content-Type" => content_type })

          result = client.download(url: avatar_url, io: io)

          expect(result[:bytes_written]).to eq(1000)
        end
      end

      context "when body is within max_size" do
        it "downloads successfully" do
          stub_request(:get, avatar_url)
            .to_return(status: 200, body: image_data, headers: { "Content-Type" => content_type })

          result = client.download(url: avatar_url, io: io, max_size: 1000)

          expect(result[:bytes_written]).to eq(image_data.bytesize)
        end
      end
    end

    context "with different IO types" do
      it "works with StringIO" do
        stub_request(:get, avatar_url)
          .to_return(status: 200, body: image_data, headers: { "Content-Type" => content_type })

        string_io = StringIO.new.tap { |s| s.set_encoding(Encoding::ASCII_8BIT) }
        client.download(url: avatar_url, io: string_io)

        string_io.rewind
        expect(string_io.read).to eq(image_data.b)
      end

      it "works with Tempfile" do
        stub_request(:get, avatar_url)
          .to_return(status: 200, body: image_data, headers: { "Content-Type" => content_type })

        tempfile = Tempfile.new(["test", ".tmp"], binmode: true)
        begin
          client.download(url: avatar_url, io: tempfile)

          tempfile.rewind
          expect(tempfile.read).to eq(image_data.b)
        ensure
          tempfile.close
          tempfile.unlink
        end
      end

      it "works with File" do
        stub_request(:get, avatar_url)
          .to_return(status: 200, body: image_data, headers: { "Content-Type" => content_type })

        Dir.mktmpdir do |dir|
          path = File.join(dir, "test.tmp")
          File.open(path, "wb") do |file|
            client.download(url: avatar_url, io: file)
          end

          expect(File.read(path, mode: "rb")).to eq(image_data.b)
        end
      end
    end
  end

  describe "configuration" do
    it "uses default timeout of 30 seconds" do
      expect(client.timeout).to eq(30)
    end

    it "accepts custom timeout" do
      custom_client = described_class.new(timeout: 60)
      expect(custom_client.timeout).to eq(60)
    end
  end
end
