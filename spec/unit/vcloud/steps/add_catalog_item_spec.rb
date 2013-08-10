require 'spec_helper'

module VCloudCloud
  module Steps

    describe AddCatalogItem do
      before(:each) do
        @catalog_type = "vcloud_type"
        @catalog_add_item_link = "add_item_link"

        @catalog = double("vcloud catalog")
        @catalog.stub(:add_item_link) { @catalog_add_item_link }

        @catalog_item_name = "vcloud item name"
        @catalog_item = double("vcloud catalog item").as_null_object
        @catalog_item.stub(:name) { @catalog_item_name }

        @client = double("vcloud client").as_null_object
        @client.stub(:catalog) do |param|
          @catalog if param == @catalog_type
        end
        @client.stub(:invoke) do |method, link, params|
          "#{method}:#{link}:#{params[:payload].name}"
        end
      end

      it "invokes add_catalog_item step" do
        @catalog.should_receive(:add_item_link).once

        @catalog_item.should_receive(:name).twice

        @client.should_receive(:catalog).once.with(@catalog_type)
        @client.should_receive(:invoke).once.with(:post, @catalog_add_item_link, kind_of(Hash))

        Transaction.perform("add catalog item", @client) do |s|
          s.next described_class, @catalog_type, @catalog_item
          s.state[:catalog_item].should eql "post:#{@catalog_add_item_link}:#{@catalog_item_name}"
        end

      end
    end

  end
end
