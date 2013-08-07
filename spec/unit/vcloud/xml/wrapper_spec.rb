require 'spec_helper'

module VCloudSdk
  module Xml

    describe WrapperFactory do
      valid_type_name = "AdminCatalog"
      invalid_type_name = "InvalidClass"

      valid_xml = "<#{valid_type_name}/>"
      invalid_xml = "<#{invalid_type_name}/>"

      describe :wrap_document do
        it "successfully creates a specialized wrapper" do
          wrapper = WrapperFactory.wrap_document valid_xml
          wrapper.should be_an_instance_of AdminCatalog
        end

        it "fails to create specialized wrapper and creates a generic wrapper instead" do
          wrapper = WrapperFactory.wrap_document invalid_xml
          wrapper.should be_an_instance_of Wrapper
        end
      end

      describe :wrap_node do
        it "successfully creates a specialized wrapper" do
          doc = Nokogiri::XML valid_xml
          wrapper = WrapperFactory.wrap_node doc.root, nil
          wrapper.should be_an_instance_of AdminCatalog
        end

        it "fails to create specialized wrapper and creates a generic wrapper instead" do
          doc = Nokogiri::XML invalid_xml
          wrapper = WrapperFactory.wrap_node doc.root, nil
          wrapper.should be_an_instance_of Wrapper
        end
      end

      describe :wrap_nodes do
        it "creates a list of specialized and generic nodes" do
          nodes = [Nokogiri::XML(valid_xml).root, Nokogiri::XML(invalid_xml).root]
          wrappers = WrapperFactory.wrap_nodes nodes, nil, nil
          wrappers.map() {|w| w.class}.should match_array([AdminCatalog, Wrapper])
        end
      end

      describe :find_wrapper_class do
        it "successfully returns specialized wrapper class" do
          wrapper_class = WrapperFactory.find_wrapper_class valid_type_name
          wrapper_class.should equal AdminCatalog
        end

        it "fails to find a specialized wrapper class and returns the generic" do
          wrapper_class = WrapperFactory.find_wrapper_class invalid_type_name
          wrapper_class.should equal Wrapper
        end
      end

      describe :create_instance do
        it "successfully creates object" do
          wrapper = WrapperFactory.create_instance valid_type_name
          wrapper.should be_an_instance_of AdminCatalog
        end

        it "fails to create object" do
          expect{WrapperFactory.create_instance invalid_type_name }.to raise_exception Bosh::Clouds::CpiError
        end
      end

    end

  end
end
