require "spec_helper"

module VCloudCloud
  class VCloudClient
    attr_accessor :cache, :org_link
  end

  describe VCloudClient do
    logger = Bosh::Clouds::Config.logger
    let(:settings) { Test.vcd_settings }
    let(:client) { described_class.new(settings, logger)}

    describe '.initialize' do
      it 'read control settings from configuration file' do
        verify_control_settings :@wait_max => 400, :@wait_delay => 10, :@retry_max => 5, :@retry_delay => 500, :@cookie_timeout => 1200, :@old_task_threshold => 600
      end

      it 'use default control settings if not specified in configuration file' do
        settings['entities']['control'] = nil
        verify_control_settings :@wait_max => VCloudClient::WAIT_MAX, :@wait_delay => VCloudClient::WAIT_DELAY, \
          :@retry_max => VCloudClient::RETRY_MAX, :@retry_delay => VCloudClient::RETRY_DELAY, :@cookie_timeout => VCloudClient::COOKIE_TIMEOUT, :@old_task_threshold => VCloudClient::OLD_TASK_THRESHOLD
      end

      private
      def verify_control_settings(control_settings)
        control_settings.each do |instance_variable_name, target_numeric_value|
          instance_variable = client.instance_variable_get(instance_variable_name)
          expect(instance_variable).to eql target_numeric_value
        end
      end
    end

    describe '.invoke' do
      it 'fetches auth header' do
        version_response = double('version_response')
        url_node = double('login url node')
        allow(url_node).to receive_message_chain('login_url.content').and_return '/api/sessions'
        expect(client).to receive(:wrap_response).with(version_response).and_return url_node

        login_response = double('login_response')
        cookies = "cookies string"
        auth_token = {:x_vcloud_authorization => auth_token }
        expect(login_response).to receive(:headers).and_return auth_token
        expect(login_response).to receive(:cookies).and_return cookies
        base_url = URI.parse(settings['url'])

        session = double("session")
        expect(session).to receive(:entity_resolver)
        expect(session).to receive(:org_link)
        expect(client).to receive(:wrap_response).with(login_response).and_return session

        info_response = double("info response")
        expect(info_response).to receive(:code).and_return 204
        # version
        expect(RestClient::Request).to receive(:execute) do |arg|
          expect(arg[:url]).to eq base_url.merge('/api/versions').to_s
          expect(arg[:cookies]).to be_nil
        end.and_return version_response
        # login
        expect(RestClient::Request).to receive(:execute) do |arg|
          expect(arg[:url]).to eq base_url.merge("/api/sessions").to_s
          expect(arg[:cookies]).to be_nil
        end.and_return login_response
        # /info
        expect(RestClient::Request).to receive(:execute) do |arg|
          expect(arg[:url]).to eq base_url.merge("/info").to_s
          expect(arg[:cookies]).to be cookies
        end.and_return info_response

        client.invoke :get, "/info"
      end

      it 'puts a request identifier in the request' do
        wrapped_entity_double = double(
          'wrapped entity',
          entity_resolver: nil,
          login_url: double(
            'login_url',
            content: 'http://example.com/login/url'
          ),
          org_link: nil
        )
        allow(client).to receive(:wrap_response).and_return(wrapped_entity_double)
        prevous_request_id = nil
        expect(RestClient::Request).to receive(:execute).at_least(:once) do |args|
          expect(args[:headers]['X-VMWARE-VCLOUD-CLIENT-REQUEST-ID']).to_not be_nil
          expect(args[:headers]['X-VMWARE-VCLOUD-CLIENT-REQUEST-ID']).to_not eq(prevous_request_id)
          prevous_request_id = args[:headers]['X-VMWARE-VCLOUD-CLIENT-REQUEST-ID']
        end.and_return(double(RestClient::Response, code: 204, headers: {x_vcloud_authorization: 'fake token'}, cookies: nil))
        client.invoke :get, '/info', no_wrap: true
      end

      context "when receiving an error response" do
        let(:response) { double('RestClient::Response') }

        before :each do
          allow_any_instance_of(RestClient::Request).to receive(:execute).and_yield(response, nil, nil)
          allow(response).to receive(:code)
          allow(response).to receive(:headers)
        end

        it "throws a vm exists error" do
          error_xml = '<Error majorErrorCode="400" message="[ 5bdd3f05-8130-43f3-8941-58009bd0ea10 ] There is already a VM named &quot;18369d52-151a-4fa3-87ee-c5dad9288f9f&quot;." minorErrorCode="BAD_REQUEST"></Error>'
          allow(response).to receive(:body).and_return(error_xml)
          allow(response).to receive(:return!).and_raise(RestClient::BadRequest)
          expect{client.invoke(:method, "/something")}.to raise_error(ObjectExistsError)
        end

        it "throws a generic response error" do
           error_xml = '<Error majorErrorCode="400" message="[ 5bdd3f05-8130-43f3-8941-58009bd0ea10 ] Other error message." minorErrorCode="BAD_REQUEST"></Error>'
           allow(response).to receive(:body).and_return(error_xml)
           allow(response).to receive(:return!).and_raise(RestClient::BadRequest)
           expect{client.invoke(:method, "/something")}.to raise_error(RestClient::BadRequest)
        end

        it "throws a internal server error" do
          error_xml = '<Error majorErrorCode="500" message="[ 98843fff-33c4-4ef8-b1eb-d1f9a54b63d7 ] Unable to perform this action. Contact your cloud administrator." minorErrorCode="INTERNAL_SERVER_ERROR"></Error>'
          allow(response).to receive(:body).and_return(error_xml)
          allow(response).to receive(:return!).and_raise(RestClient::InternalServerError)
          expect{client.invoke(:method, "/something")}.to raise_error(RestClient::InternalServerError)
        end

        it "throws a runtime error" do
          error_xml = ''
          allow(response).to receive(:body).and_return(error_xml)
          allow(response).to receive(:return!).and_raise(RuntimeError)
          expect{client.invoke(:method, "/something")}.to raise_error(RuntimeError)
        end
      end
    end

    describe "trivia methods" do
      it "reads properties from settings" do
        [
          [:org_name, :organization],
          [:vdc_name, :virtual_datacenter],
          [:vapp_catalog_name, :vapp_catalog],
          [:media_catalog_name, :media_catalog],
        ].each do |props|
          method, prop = props
          expect(client.send(method)).to eq settings['entities'][prop.to_s]
        end
      end
    end

    describe ".org" do
      it "reads cache" do
        expect(client.cache).to receive(:get).with(:org)

        client.org
      end

      it "fetch org info when cache is missing" do
        client.cache.clear
        org_link = "org_link"
        client.org_link = org_link
        expect(client).to receive(:session)
        expect(client).to receive(:resolve_link).with(org_link)

        client.org
      end
    end

    describe ".vdc" do
      it "reads cache" do
        expect(client.cache).to receive(:get).with(:vdc)

        client.vdc
      end

      it "fetch vdc info when cache is missing" do
        client.cache.clear
        vdc_link = "vdc_link"
        org = double("org")
        expect(org).to receive(:vdc_link).with(client.vdc_name).
          and_return(vdc_link)
        expect(client).to receive(:org).and_return(org)
        expect(client).to receive(:resolve_link).with(vdc_link)

        client.vdc
      end

      it "raise error when vdc is not found" do
        client.cache.clear
        vdc_link = "vdc_link"
        org = double("org")
        expect(org).to receive(:vdc_link).with(client.vdc_name).
          and_return(nil)
        expect(client).to receive(:org).and_return(org)

        expect{client.vdc}.to raise_error(
          ObjectNotFoundError, /#{client.vdc_name}/)
      end
    end

    describe ".catalog_item" do
      it "return the first matched item in catalog" do
        catalog_type = :media
        catalog_name = "demo"
        type = VCloudSdk::Xml::MEDIA_TYPE[:MEDIA]
        items = [ "i1", "i2" ]
        object1 = double("o1")
        expect(object1).to receive(:entity).and_return({'type' => type})
        expect(client).to receive(:resolve_link).and_return object1
        catalog = double("catalog")
        expect(catalog).to receive(:catalog_items).with(catalog_name).
          and_return(items)
        expect(client).to receive(:catalog).with(catalog_type).
          and_return(catalog)

        client.catalog_item(catalog_type, catalog_name,type)
      end
    end

    describe ".reload" do
      it "reload object from link" do
        object = double("o1")
        link = "obj_link"
        expect(object).to receive(:href).and_return(link)
        expect(client).to receive(:invoke).and_return object

        expect(client.reload(object)).to eq object
      end
    end

    describe ".wait_entity" do
      let(:task_id) { 'fake_task_id' }
      let(:task_operation) { 'fake_task_operation' }
      let(:task_details) { 'fake_task_details' }


      it "wait for running tasks" do
        entity = double("entity")
        allow(client).to receive(:reload) do |args|
          args
        end
        task = double("task")
        expect(task).to receive(:urn).and_return "urn"
        expect(task).to receive(:operation).and_return "update"
        allow(task).to receive(:status).and_return VCloudSdk::Xml::TASK_STATUS[:SUCCESS]
        allow(entity).to receive(:running_tasks) {[task]}
        allow(entity).to receive(:prerunning_tasks) {[]}
        allow(entity).to receive(:tasks) {[task]}

        client.wait_entity(entity)
      end

      it "raise error when running task failed" do
        entity = double("entity")
        allow(client).to receive(:reload) do |args|
          args
        end
        task = double("task")
        allow(task).to receive(:urn).and_return(task_id)
        allow(task).to receive(:operation).and_return(task_operation)
        allow(task).to receive(:details).and_return(task_details)
        allow(task).to receive(:status).and_return VCloudSdk::Xml::TASK_STATUS[:ERROR]

        allow(entity).to receive(:running_tasks) {[task]}
        allow(entity).to receive(:prerunning_tasks) {[]}
        allow(entity).to receive(:tasks) {[task]}

        raise_error_info =Regexp.new("Task #{task_id} #{task_operation} completed unsuccessfully, Details:#{task_details}")
        expect{client.wait_entity(entity)}.to raise_error raise_error_info
      end

      it "raise error when completed task failed" do
        entity = double("entity")
        allow(client).to receive(:reload) do |args|
          args
        end
        task = double("task")
        allow(task).to receive(:status).and_return VCloudSdk::Xml::TASK_STATUS[:ERROR]
        allow(task).to receive(:urn).and_return(task_id)
        allow(task).to receive(:operation).and_return(task_operation)
        allow(task).to receive(:details).and_return(task_details)
        allow(task).to receive(:start_time).and_return(Time.now)

        allow(entity).to receive(:running_tasks) {[]}
        allow(entity).to receive(:prerunning_tasks) {[]}
        allow(entity).to receive(:tasks) {[task, task]}

        task_info = "Task #{task_id} #{task_operation}, Details:#{task_details}"
        raise_error_info =Regexp.new("Some tasks failed: #{task_info}; #{task_info}")
        expect{client.wait_entity(entity)}.to raise_error raise_error_info
      end
      
      it "idenitifies an old task" do
        task = double("task")
        allow(task).to receive(:start_time).and_return(Time.parse("2016-05-11T10:08:17.880+01:00"))
        expect(client.old_task?(task)).to eq true
      end
      
      it "ignores newer tasks" do
        task = double("task")
        allow(task).to receive(:start_time).and_return Time.now - 60
        expect(client.old_task?(task)).to eq false
      end
      
      it "filters old tasks appropriately" do
        task1 = double("task")
        allow(task1).to receive(:status).and_return "failed"
        allow(task1).to receive(:start_time).and_return Time.parse("2016-05-11T10:08:17.880+01:00")
        
        task2 = double("task")
        allow(task2).to receive(:status).and_return "failed"
        allow(task2).to receive(:start_time).and_return Time.parse("2016-05-11T10:08:17.880+01:00")
        
        task3 = double("task")
        allow(task3).to receive(:status).and_return "failed"
        allow(task3).to receive(:start_time).and_return Time.now
        
        entity = double("entity")
        allow(entity).to receive(:tasks) {[task1,task2,task3]}
        
        failed_tasks = client.get_failed_tasks(entity)
        
        expect(failed_tasks.length).to be 1
        expect(failed_tasks[0].start_time).to eq task3.start_time
      end
      
    end
  end
end
