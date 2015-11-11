require 'spec_helper'

describe Cukerail do
  let(:sender){Testrail::Cukerail.new}

  context 'no failed step' do
    before(:each) do
      sender.testrail_api_client = instance_double(TestRail::APIClient)
    end

    it "sends 'test failed before any steps ran' to TestRail" do
      # allow(sender).to receive(:failed_step).and_return({
    end

  end

end
