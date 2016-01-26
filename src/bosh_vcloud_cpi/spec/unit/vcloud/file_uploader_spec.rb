require "spec_helper"

module VCloudCloud
  describe FileUploader do
    let(:upload_link) { "http://fakedomain.com/" }
    let(:size) { 10 }
    let(:stream) do
      stream = double("stream")
      stream
    end

    let(:options) { { cookie: { key: "value" } } }
    let(:request) do
      request = double("http_request")
      request
    end

    let(:connection) do
      connection = double("connection")
      allow(connection).to receive(:use_ssl?) { false }
      allow(connection).to receive(:use_ssl=)
      connection
    end

    let(:response) do
      response = double("response")
      allow(response).to receive(:body) { "body" }
      response
    end

    describe "#upload" do
      it "uploads stream to url" do
        allow(Net::HTTP::Put).to receive(:new).with(upload_link, anything) { request }
        allow(Net::HTTP).to receive(:new) { connection }
        allow(request).to receive(:body_stream=).with(stream)
        expect(connection).to receive(:start).and_yield(connection)
        expect(response).to receive(:read_body)
        expect(response).to receive(:code) { "201" }
        expect(connection).to receive(:request).with(request).
          and_yield(response).and_return(response)

        described_class.upload(upload_link, size, stream, options)
      end

      it "raise error when request failed" do
        allow(Net::HTTP::Put).to receive(:new).with(upload_link, anything) { request }
        allow(Net::HTTP).to receive(:new) { connection }
        allow(request).to receive(:body_stream=).with(stream)
        expect(connection).to receive(:start).and_yield(connection)
        expect(response).to receive(:read_body)
        expect(response).to receive(:code).at_least(2).times { "401" }
        expect(connection).to receive(:request).with(request).
          and_yield(response).and_return(response)

        expect {
          described_class.upload(upload_link, size, stream, options)
        }.to raise_error /Error Response/

      end
    end
  end
end
