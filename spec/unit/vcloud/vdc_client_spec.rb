require "spec_helper"

module VCloudCloud

  describe VCloudClient do
    logger = Bosh::Clouds::Config.logger
    let(:settings) { Test.vcd_settings }
    let(:client) { described_class.new(settings, logger)}

    describe ".invoke" do
      it "fetch auth header" do
        login_response = double("login_response")
        cookies = "cookies string"
        auth_token = {:x_vcloud_authorization => auth_token }
        login_response.should_receive(:headers).and_return auth_token
        login_response.should_receive(:cookies).and_return cookies
        base_url = URI.parse(settings['url'])
        login_response.should_receive(:code).and_return 201

        session = double("session")
        session.should_receive(:entity_resolver)
        session.should_receive(:org_link)
        client.should_receive(:wrap_response).with(login_response).and_return session

        info_response = double("info response")
        info_response.should_receive(:code).and_return 204
        # login
        RestClient::Request.should_receive(:execute) do |arg|
          arg[:url].should == base_url.merge("/api/sessions").to_s
          arg[:cookies].should be_nil
        end.and_return login_response
        # /info
        RestClient::Request.should_receive(:execute) do |arg|
          arg[:url].should == base_url.merge("/info").to_s
          arg[:cookies].should == cookies
        end.and_return info_response

        client.invoke :get, "/info"
      end
    end
  end
end
