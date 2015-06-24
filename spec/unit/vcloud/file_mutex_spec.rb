require 'spec_helper'
require 'timeout'

module VCloudCloud
  describe FileMutex do

    before { @location = Dir.mktmpdir('locks') }

    it 'prevents concurrent execution of protected blocks' do
      sum = 0

      thr = Thread.new do
        mutex = FileMutex.new(@location)
        expect(mutex).to_not(be_nil)
        mutex.synchronize do
          sum += 1
          sleep 1
        end
      end

      sleep 0.1 # make sure the thread is spawned before we move on...

      mutex2 = FileMutex.new(@location)

      expect {
        Timeout::timeout(0.001) { mutex2.synchronize { sum += 1 } }
      }.to raise_exception (Timeout::Error)

      thr.join()
      expect(sum).to eq(1)
    end
  end
end
