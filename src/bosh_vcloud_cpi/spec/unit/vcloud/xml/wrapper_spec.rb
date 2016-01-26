require 'spec_helper'

module VCloudSdk
  module Xml

    describe WrapperFactory do
      before(:each) do
        @valid_type_name = "AdminCatalog"
        @invalid_type_name = "InvalidClass"

        @valid_xml = "<#{@valid_type_name}/>"
        @invalid_xml = "<#{@invalid_type_name}/>"
      end

      describe :wrap_document do
        it "successfully creates a admin catalog wrapper" do
          wrapper = WrapperFactory.wrap_document @valid_xml
          expect(wrapper).to be_an_instance_of AdminCatalog
        end

        it "successfully creates an error wrapper" do
          error_xml = "<Error/>"
          wrapper = WrapperFactory.wrap_document error_xml
          expect(wrapper).to be_an_instance_of Error
        end

        it "returns the error number and the error message" do
          error_xml = '<Error majorErrorCode="400" message="[ 5bdd3f05-8130-43f3-8941-58009bd0ea10 ] There is already a VM named &quot;18369d52-151a-4fa3-87ee-c5dad9288f9f&quot;." minorErrorCode="BAD_REQUEST"></Error>'
          wrapper = WrapperFactory.wrap_document error_xml
          expect(wrapper).to be_an_instance_of Error
          expect(wrapper.major_error).to eq('400')
          expect(wrapper.minor_error).to eq('BAD_REQUEST')
          expect(wrapper.error_msg).to eq('[ 5bdd3f05-8130-43f3-8941-58009bd0ea10 ] There is already a VM named "18369d52-151a-4fa3-87ee-c5dad9288f9f".')
        end

        it "fails to create specialized wrapper and creates a generic wrapper instead" do
          wrapper = WrapperFactory.wrap_document @invalid_xml
          expect(wrapper).to be_an_instance_of Wrapper
        end
      end

      describe :wrap_node do
        it "successfully creates a specialized wrapper" do
          doc = Nokogiri::XML @valid_xml
          wrapper = WrapperFactory.wrap_node doc.root, nil
          expect(wrapper).to be_an_instance_of AdminCatalog
        end

        it "fails to create specialized wrapper and creates a generic wrapper instead" do
          doc = Nokogiri::XML @invalid_xml
          wrapper = WrapperFactory.wrap_node doc.root, nil
          expect(wrapper).to be_an_instance_of Wrapper
        end
      end

      describe :wrap_nodes do
        it "creates a list of specialized and generic nodes" do
          nodes = [Nokogiri::XML(@valid_xml).root, Nokogiri::XML(@invalid_xml).root]
          wrappers = WrapperFactory.wrap_nodes nodes, nil, nil
          expect(wrappers.map {|w| w.class}).to match_array [AdminCatalog, Wrapper]
        end
      end

      describe :find_wrapper_class do
        it "successfully returns specialized wrapper class" do
          wrapper_class = WrapperFactory.find_wrapper_class @valid_type_name
          expect(wrapper_class).to equal AdminCatalog
        end

        it "fails to find a specialized wrapper class and returns the generic" do
          wrapper_class = WrapperFactory.find_wrapper_class @invalid_type_name
          expect(wrapper_class).to equal Wrapper
        end
      end

      describe :create_instance do
        it "successfully creates object" do
          wrapper = WrapperFactory.create_instance @valid_type_name
          expect(wrapper).to be_an_instance_of AdminCatalog
        end

        it "fails to create object" do
          expect{WrapperFactory.create_instance @invalid_type_name}.to raise_exception Bosh::Clouds::CpiError
        end
      end
    end

    describe Wrapper do
      before(:each) do
        @incomplete_doc = "<SomeXml><SomeItem/></SomeXml>"
        @incomplete_wrapper = Wrapper.new Nokogiri::XML(@incomplete_doc)

        @wp_name = "test"
        @wp_href = "http://test.com"
        @wp_id = "tid"
        @wp_type = "ttype"
        @wp_content = "some text"

        @complete_doc_no_ns = "<SomeXml name='#{@wp_name}' href='#{@wp_href}' id='#{@wp_id}' type='#{@wp_type}'>#{@wp_content}</SomeXml>"
        @complete_wrapper_no_ns = Wrapper.new Nokogiri::XML(@complete_doc_no_ns)

        @wp_ns_attrib = "tattrib"
        @wp_ns = "ns1"
        @wp_ns_href = "http://www.test.com/test"
        @wp_no_prefix_ns_href = "http://www.test.com/test_no_prefix"
        @complete_doc_with_ns = "<#{@wp_ns}:SomeXml xmlns:#{@wp_ns}='#{@wp_ns_href}' xmlns='#{@wp_no_prefix_ns_href}' name='#{@wp_name}' href='#{@wp_href}' id='#{@wp_id}' type='#{@wp_type}' #{@wp_ns}:#{@wp_ns_attrib}='#{@wp_ns_attrib}'><#{@wp_ns}:SomeItem/><#{@wp_ns}:SomeItem #{@wp_ns_attrib}='#{@wp_ns_attrib}'/></#{@wp_ns}:SomeXml>"
        @complete_wrapper_with_ns = Wrapper.new Nokogiri::XML(@complete_doc_with_ns)
      end

      describe :initialize do
        it "creates wrapper from document" do
          wrapper = Wrapper.new Nokogiri::XML(@incomplete_doc)
          expect(wrapper).to be_an_instance_of Wrapper
        end

        it "creates wrapper from node" do
          wrapper = Wrapper.new Nokogiri::XML(@incomplete_doc).root
          expect(wrapper).to be_an_instance_of Wrapper
        end

        it "fails to create object when called with invalid param" do
          expect{Wrapper.new "some text"}.to raise_exception NoMethodError
          expect{Wrapper.new 10}.to raise_exception NoMethodError
        end
      end

      describe :doc_namespaces do
        context "wrapper without namespace" do
          it "returns an empty array" do
            expect(@complete_wrapper_no_ns.doc_namespaces).to match_array []
          end
        end

        context "wrapper with namespace" do
          it "returns the list of namespaces" do
            expect(@complete_wrapper_with_ns.doc_namespaces.length).to eq 2
            expect(@complete_wrapper_with_ns.doc_namespaces[0].prefix).to eq @wp_ns
            expect(@complete_wrapper_with_ns.doc_namespaces[0].href).to eq @wp_ns_href
            expect(@complete_wrapper_with_ns.doc_namespaces[1].prefix).to be_nil
            expect(@complete_wrapper_with_ns.doc_namespaces[1].href).to eq @wp_no_prefix_ns_href
          end
        end
      end

      describe :xpath do
        context "incomplete wrapper" do
          it "finds and element for the path" do
            xpath_value = "/SomeXml/SomeItem"
            item_classes = @incomplete_wrapper.xpath(xpath_value).map{|i| i.class }
            expect(item_classes).to match_array [Wrapper]
          end

          it "fails to find element due to missing element" do
            xpath_value = "/SomeXml/OtherItem"
            item_classes = @incomplete_wrapper.xpath(xpath_value).map{|i| i.class}
            expect(item_classes).to match_array []
          end
        end

        context "complete wrapper with namespace" do
          it "finds and element for the path" do
            xpath_value = "/#{@wp_ns}:SomeXml/#{@wp_ns}:SomeItem"
            item_classes = @complete_wrapper_with_ns.xpath(xpath_value).map() {|i| i.class}
            expect(item_classes).to match_array [Wrapper, Wrapper]
          end

          it "fails to find element due to missing namespace in the path" do
            xpath_value = "/#{@wp_ns}:SomeXml/SomeItem"
            item_classes = @complete_wrapper_with_ns.xpath(xpath_value).map() {|i| i.class}
            expect(item_classes).to match_array []
          end

          it "fails to find element due to missing element" do
            xpath_value = "/#{@wp_ns}:SomeXml/#{@wp_ns}:OtherItem"
            item_classes = @complete_wrapper_with_ns.xpath(xpath_value).map() {|i| i.class}
            expect(item_classes).to match_array []
          end
        end
      end

      describe :href do
        context "incomplete wrapper" do
          it "returns nil" do
            expect(@incomplete_wrapper.href).to be_nil
          end
        end

        context "complete wrapper" do
          it "returns correct value" do
            expect(@complete_wrapper_with_ns.href).to eql @wp_href
          end
        end
      end

      describe :name do
        context "incomplete wrapper" do
          it "returns nil" do
            expect(@incomplete_wrapper.name).to be_nil
          end
        end

        context "complete wrapper" do
          it "returns correct value" do
            expect(@complete_wrapper_with_ns.name).to eql @wp_name
          end
        end
      end

      describe :urn do
        context "incomplete wrapper" do
          it "returns nil" do
            expect(@incomplete_wrapper.urn).to be_nil
          end
        end

        context "complete wrapper" do
          it "returns correct value" do
            expect(@complete_wrapper_with_ns.urn).to eql @wp_id
          end
        end
      end

      describe :type do
        context "incomplete wrapper" do
          it "returns nil" do
            expect(@incomplete_wrapper.type).to be_nil
          end
        end

        context "complete wrapper" do
          it "returns correct value" do
            expect(@complete_wrapper_with_ns.type).to eql @wp_type
          end
        end
      end

      describe :attribute_with_ns do
        context "complete wrapper without namespace" do
          it "returns the attribute 'name'" do
            attrib = @complete_wrapper_no_ns.attribute_with_ns("name", nil)
            expect(attrib).to be_an_instance_of Nokogiri::XML::Attr
            expect(attrib.value).to eql @wp_name
          end

          it "returns nil for unknown attribute" do
            attrib = @complete_wrapper_no_ns.attribute_with_ns("unknown", nil)
            expect(attrib).to be_nil
          end
        end

        context "complete wrapper with namespace" do
          it "returns the attribute '#{@wp_ns_attrib}'" do
            attrib = @complete_wrapper_with_ns.attribute_with_ns(@wp_ns_attrib, @wp_ns_href)
            expect(attrib).to be_an_instance_of Nokogiri::XML::Attr
            expect(attrib.value).to eql @wp_ns_attrib
          end

          it "returns nil due to missing namespace information" do
            attrib = @complete_wrapper_with_ns.attribute_with_ns(@wp_ns_attrib, nil)
            expect(attrib).to be_nil
          end

          it "return nil for unknown attribute" do
            attrib = @complete_wrapper_with_ns.attribute_with_ns("unknown", @wp_ns_href)
            expect(attrib).to be_nil
          end
        end
      end

      describe :create_xpath_query do
        context "complete wrapper without namespace" do
          it "raises a CpiError exception due to unknown namespace" do
            expect{@complete_wrapper_no_ns.create_xpath_query("Foo", Hash.new, true, @wp_ns_href)}.to raise_exception Bosh::Clouds::CpiError
          end

          it "raises a CpiError exception due to nil namespace" do
            expect{@complete_wrapper_no_ns.create_xpath_query("Foo", Hash.new, true, nil)}.to raise_exception Bosh::Clouds::CpiError
          end
        end

        context "complete wrapper with namespace" do
          it "returns the immediate xpath" do
            xpath = @complete_wrapper_with_ns.create_xpath_query("Foo", nil, true, @wp_ns_href)
            expect(xpath).to eql "#{@wp_ns}:Foo"
          end

          it "returns the immediate path with one attribute filter" do
            attrs = {"name" => "test"}
            xpath = @complete_wrapper_with_ns.create_xpath_query("Foo", attrs, true, @wp_ns_href)
            expect(xpath).to eql "#{@wp_ns}:Foo[@name=\"test\"]"
          end

          it "returns the immediate path with multiple attribute filters" do
            attrs = {"name" => "test", "id" => "tid"}
            xpath = @complete_wrapper_with_ns.create_xpath_query("Foo", attrs, true, @wp_ns_href)
            expect(xpath).to eql "#{@wp_ns}:Foo[@name=\"test\" and @id=\"tid\"]"
          end

          it "returns the deep xpath" do
            xpath = @complete_wrapper_with_ns.create_xpath_query("Foo", Hash.new, false, @wp_ns_href)
            expect(xpath).to eql ".//#{@wp_ns}:Foo"
          end

          it "returns the deep xpath with one attribute filter" do
            attrs = {"name" => "test"}
            xpath = @complete_wrapper_with_ns.create_xpath_query("Foo", attrs, false, @wp_ns_href)
            expect(xpath).to eql ".//#{@wp_ns}:Foo[@name=\"test\"]"
          end

          it "raises a CpiError exception due to unknown namespace" do
            expect{@complete_wrapper_no_ns.create_xpath_query("Foo", Hash.new, true, "http://unknown.com")}.to raise_exception Bosh::Clouds::CpiError
          end
        end
      end

      describe :create_qualified_name do
        context "complete wrapper without namespace" do
          it "raises a CpiError exception due to unknown namespace" do
            expect{@complete_wrapper_no_ns.create_qualified_name("Foo", @wp_ns_href)}.to raise_exception Bosh::Clouds::CpiError
          end

          it "raises a CpiError exception due to nil namespace" do
            expect{@complete_wrapper_no_ns.create_qualified_name("Foo", nil)}.to raise_exception Bosh::Clouds::CpiError
          end
        end

        context "complete wrapper with namespace" do
          it "returns the name with prefix" do
            name = @complete_wrapper_with_ns.create_qualified_name("Foo", @wp_ns_href)
            expect(name).to eql "#{@wp_ns}:Foo"
          end

          it "returns the name with 'xmlns' prefix" do
            name = @complete_wrapper_with_ns.create_qualified_name("Foo", @wp_no_prefix_ns_href)
            expect(name).to eql "xmlns:Foo"
          end

          it "raises a CpiError exception due to unknown namespace" do
            expect{@complete_wrapper_with_ns.create_qualified_name("Foo", "http://unknown.com")}.to raise_exception Bosh::Clouds::CpiError
          end

          it "raises a CpiError exception due to nil namespace" do
            expect{@complete_wrapper_with_ns.create_qualified_name("Foo", nil)}.to raise_exception Bosh::Clouds::CpiError
          end
        end
      end

      describe :get_nodes do
        context "complete wrapper without namespace" do
          it "raises a CpiError exception due to unknown namespace" do
            expect{@complete_wrapper_no_ns.get_nodes("SomeXml", nil, false, @wp_ns_href)}.to raise_exception Bosh::Clouds::CpiError
          end

          it "raises a CpiError exception due to nil namespace" do
            expect{@complete_wrapper_no_ns.get_nodes("SomeXml", nil, false, nil)}.to raise_exception Bosh::Clouds::CpiError
          end
        end

        context "complete wrapper with namespace" do
          it "return the matching item node" do
            item_classes = @complete_wrapper_with_ns.get_nodes("SomeItem", nil, false, @wp_ns_href).map{|i| i.class }
            expect(item_classes).to match_array [Wrapper, Wrapper]
          end

          it "return the matching item with attribute filtering node" do
            attribs = { @wp_ns_attrib => @wp_ns_attrib }
            item_classes = @complete_wrapper_with_ns.get_nodes("SomeItem", attribs, false, @wp_ns_href).map{|i| i.class }
            expect(item_classes).to match_array [Wrapper]
          end

          it "return no items due to incorrect namespace" do
            item_classes = @complete_wrapper_with_ns.get_nodes("SomeItem", nil, false, @wp_no_prefix_ns_href).map{|i| i.calss}
            expect(item_classes).to match_array []
          end

          it "return no items due to incorrect item-name" do
            item_classes = @complete_wrapper_with_ns.get_nodes("OtherItem", nil, false, @wp_no_prefix_ns_href).map{|i| i.calss}
            expect(item_classes).to match_array []
          end
        end
      end

      describe :[] do
        context "complete wrapper with namespace" do
          it "returns attribute value for non-namespace attribute" do
            expect(@complete_wrapper_with_ns["name"]).to eql @wp_name
          end

          it "returns attribute value for namespaced attribute" do
            expect(@complete_wrapper_with_ns["#{@wp_ns}:#{@wp_ns_attrib}"]).to eql @wp_ns_attrib
          end

          it "returns nil when attribute does not exist" do
            expect(@complete_wrapper_with_ns["unknown"]).to be_nil
          end
        end
      end

      describe :[]= do
        context "complete wrapper with namespace" do
          it "modifies value of a non-namespace attribute" do
            new_value = "new value"
            expect(@complete_wrapper_with_ns["name"]).to eql @wp_name
            @complete_wrapper_with_ns["name"] = new_value
            expect(@complete_wrapper_with_ns["name"]).to eql new_value
          end

          it "modifies value of a namespaced attribute " do
            new_value = "new value"
            attrib_name = "#{@wp_ns}:#{@wp_ns_attrib}"
            expect(@complete_wrapper_with_ns[attrib_name]).to eql @wp_ns_attrib
            @complete_wrapper_with_ns[attrib_name] = new_value
            expect(@complete_wrapper_with_ns[attrib_name]).to eql new_value
          end

          it "adds attribute for unknown attribute" do
            new_attrib = "nattrib"
            expect(@complete_wrapper_with_ns[new_attrib]).to be_nil
            @complete_wrapper_with_ns[new_attrib] = new_attrib
            expect(@complete_wrapper_with_ns[new_attrib]).to eql new_attrib
          end

          it "adds attribute for unknown namespaced attribute" do
            new_attrib = "#{@wp_ns}:nattrib"
            expect(@complete_wrapper_with_ns[new_attrib]).to be_nil
            @complete_wrapper_with_ns[new_attrib] = new_attrib
            expect(@complete_wrapper_with_ns[new_attrib]).to eql new_attrib
          end
        end
      end

      context :content do
        context "complete wrapper no namespace with content" do
          it "retruns the content text of the root node" do
            expect(@complete_wrapper_no_ns.content).to eql @wp_content
          end
        end

        context "complete wrapper with namespace" do
          it "returns empty string for root with no content" do
            expect(@complete_wrapper_with_ns.content).to eql ""
          end
        end
      end

      context :content= do
        context "complete wrapper no namespace with content" do
          it "replaces the content text of the root node" do
            new_text = "new text"
            expect(@complete_wrapper_no_ns.content).to eql @wp_content
            @complete_wrapper_no_ns.content = new_text
            expect(@complete_wrapper_no_ns.content).to eql new_text
          end
        end

        context "complete wrapper with namespace" do
          it "adds content text for root with no content" do
            new_text = "new text"
            expect(@complete_wrapper_with_ns.content).to eql ""
            @complete_wrapper_with_ns.content = new_text
            expect(@complete_wrapper_with_ns.content).to eql new_text
          end
        end
      end

      context :== do
        context "complete wrapper no namespace with content" do
          it "returns true comparing a clone of the same object" do
            other = @complete_wrapper_no_ns.clone
            expect(@complete_wrapper_no_ns == other).to be true
          end

          it "returns false comparing a different object" do
            expect(@complete_wrapper_no_ns == @complete_wrapper_with_ns).to be false
          end
        end
      end

      context :to_s do
        context "complete wrapper no namespace with content" do
          it "returns the string representation" do
            expect(@complete_wrapper_no_ns.to_s).to eql @complete_doc_no_ns.to_s.gsub("'", "\"")
          end
        end

        context "complete wrapper with namespace" do
          it "returns the string representation" do
            to_s_result = @complete_wrapper_with_ns.to_s.each_line.inject(""){
                |xml, line| xml.concat(line.strip)}
            expect(to_s_result).to eql @complete_doc_with_ns.to_s.gsub("'", "\"")
          end
        end
      end

      context :add_child do
        before(:each) do
          @child_node_tag = "ChildNode"
          @child_wrapper = Wrapper.new Nokogiri::XML("<#{@child_node_tag}/>")
        end

        context "incomplete wrapper" do
          before(:each) do
            @expected_add_to_root_string = "<SomeXml>\n  <SomeItem/>\n  <#{@child_node_tag}/>\n</SomeXml>"
            @expected_add_to_root_with_ns_string = "<SomeXml>\n  <SomeItem/>\n  <#{@wp_ns}:#{@child_node_tag} xmlns:#{@wp_ns}=\"#{@wp_ns_href}\"/>\n</SomeXml>"
            @expected_add_to_subnode_string = "<SomeXml>\n  <SomeItem>\n    <#{@child_node_tag}/>\n  </SomeItem>\n</SomeXml>"
          end

          it "adds another wrapper to the root" do
            @incomplete_wrapper.add_child(@child_wrapper)
            expect(@incomplete_wrapper.to_s).to eql @expected_add_to_root_string
          end

          it "adds XML string to the root" do
            @incomplete_wrapper.add_child(@child_node_tag)
            expect(@incomplete_wrapper.to_s).to eql @expected_add_to_root_string
          end

          it "adds XML string to the root with ns" do
            @incomplete_wrapper.add_child(@child_node_tag, @wp_ns, @wp_ns_href)
            expect(@incomplete_wrapper.to_s).to eql @expected_add_to_root_with_ns_string
          end

          it "adds another wrapper to a subnode" do
            xml = Nokogiri::XML(@incomplete_doc)
            sub_node, = *xml.root.xpath(".//SomeItem")
            expect(sub_node).not_to be_nil

            wrapper = Wrapper.new xml
            wrapper.add_child(@child_wrapper, nil, nil, sub_node)
            expect(wrapper.to_s).to eql @expected_add_to_subnode_string
          end

          it "adds XML string to a subnode" do
            xml = Nokogiri::XML(@incomplete_doc)
            sub_node, = *xml.root.xpath(".//SomeItem")
            expect(sub_node).not_to be_nil

            wrapper = Wrapper.new xml
            wrapper.add_child(@child_node_tag, nil, nil, sub_node)
            expect(wrapper.to_s).to eql @expected_add_to_subnode_string
          end

          it "raises CpiException because prefix is nil but ns_href is not when add by tag name" do
            expect{@incomplete_wrapper.add_child(@child_node_tag, nil, @wp_ns_href)}.to raise_exception Bosh::Clouds::CpiError
          end

          it "raises CpiException when child is of unsupported type" do
            expect{@incomplete_wrapper.add_child(1)}.to raise_exception Bosh::Clouds::CpiError
          end
        end

        describe :create_child do
          context "incomplete wrapper" do
            it "creates new child node of the root" do
              node = @incomplete_wrapper.create_child(@child_node_tag)
              expect(node.to_s).to eql "<#{@child_node_tag}/>"
              expect(@incomplete_wrapper.to_s).to eql "<SomeXml>\n  <SomeItem/>\n</SomeXml>"
            end
          end
        end
      end
    end

  end
end
