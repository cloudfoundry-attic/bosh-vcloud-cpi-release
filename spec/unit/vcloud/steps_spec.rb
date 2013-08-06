require 'spec_helper'

module VCloudCloud
  describe Transaction do
    describe ".perform" do
      let(:client) do
        client = double("mock client")
        client.stub(:logger) { Bosh::Clouds::Config.logger }
        client
      end

      it "perform stpes in sequence" do
        @records = {steps: 0, value: 0}
        S1 = Class.new(Step) do
          def perform(opts)
            opts[:records][:steps] += 1
            opts[:records][:value] = 1
          end
        end

        S2 = Class.new(Step) do
          def perform(opts)
            opts[:records][:steps] += 1
            opts[:records][:value] = 2
          end
        end

        Transaction.new("two steps transaction",client).perform do |t|
          t.next S1, :records => @records
          t.next S2, :records => @records
        end

        @records[:steps].should == 2
        @records[:value].should == 2
      end

      it "should execute rollback" do
        @records = {steps: 0, value: 0}
        S3 = Class.new(Step) do
          def perform(opts)
            @opts = opts
            @opts[:records][:value] = 1
            raise "err"
          end

          def rollback
            @opts[:records][:value] = 0
          end
        end

        expect do
          Transaction.new("rollback transaction",client).perform do |t|
            t.next S3, :records => @records
          end
        end.to raise_error(StandardError, /err/)

        @records[:value].should == 0
      end
    end
  end
end
