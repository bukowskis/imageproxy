require 'spec_helper'
require 'cgi'

describe Imageproxy::Options do
  context "params in path" do
    let(:base_url) { "http://example.com/" }
    let(:source) { CGI.escape "#{base_url}IMG1.TIFF" }
    context "resize" do
      it "should accept ImageMagick Geometry strings" do
        path = "/convert/resize/#{CGI.escape('100x100>')}/source/#{source}"
        options = Imageproxy::Options.new(path, {})
        options.resize.should == "100x100>"
      end
    end
  end
end
