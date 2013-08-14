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
      connection.stub(:use_ssl?) { false }
      connection.stub(:use_ssl=)
      connection
    end

    let(:response) do
      response = double("response")
      response.stub(:body) { "body" }
      response
    end

    describe "#upload" do
      it "uploads stream to url" do
        Net::HTTP::Put.stub(:new).with(upload_link, anything) { request }
        Net::HTTP.stub(:new) { connection }
        request.stub(:body_stream=).with(stream)
        connection.should_receive(:start).and_yield(connection)
        response.should_receive(:read_body)
        response.should_receive(:code) { "201" }
        connection.should_receive(:request).with(request).
          and_yield(response).and_return(response)

        described_class.upload(upload_link, size, stream, options)
      end

      it "raise error when request failed" do
        Net::HTTP::Put.stub(:new).with(upload_link, anything) { request }
        Net::HTTP.stub(:new) { connection }
        request.stub(:body_stream=).with(stream)
        connection.should_receive(:start).and_yield(connection)
        response.should_receive(:read_body)
        response.should_receive(:code).at_least(2).times { "401" }
        connection.should_receive(:request).with(request).
          and_yield(response).and_return(response)

        expect {
          described_class.upload(upload_link, size, stream, options)
        }.to raise_error /Error Response/

      end
    end
  end
end
