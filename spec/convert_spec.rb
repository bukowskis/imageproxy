
require 'spec_helper'

describe Imageproxy::Convert do

  context "When requesting a resize" do
    before do
      @options = mock("options")
      @options.stub(:resize).and_return("123x456")
      @options.stub(:source).and_return("http://example.com/sample.png")
      @options.stub(:shape).and_return(nil)
      @options.stub(:keys).and_return([:resize, :source])
      @options.stub(:[]).with(:resize).and_return("123x456")
      @options.stub(:[]).with(:source).and_return("http://example.com/sample.png")

      @response = mock("response")
      @response.stub(:headers).and_return({:etag => '"SOMEETAG"'})
      @response.stub(:code).and_return(200)
      RestClient.stub(:get).and_return(@response)
      @response.stub(:to_str).and_return(open('public/sample.png').read)
    end

    it "resizes the image" do
      result = Imageproxy::Convert.new(@options, 1000).execute("test agent", 1234)

      image = Magick::Image.from_blob(result.stream.read).first
      image.columns.should == 123
      image.rows.should == 71
    end

    it "respects ImageMagick geometry options" do
      @options.stub(:resize).and_return("123x456!")
      result = Imageproxy::Convert.new(@options, 1000).execute("test agent", 1234)

      image = Magick::Image.from_blob(result.stream.read).first
      image.columns.should == 123
      image.rows.should ==456
    end

    it "creates an ETag based on the source's ETag and the options" do
      result = Imageproxy::Convert.new(@options, 1000).execute("test agent", 1234)

      result.headers['ETag'].should_not =~ %r{^W\/"SOMEETAG\-.+"$}
    end

    it "uses the given timeout when fetching" do
      RestClient.should_receive(:get).with("http://example.com/sample.png", :timeout => 1234, :user_agent => "test agent", :accept => '*/*').and_return(@response)

      Imageproxy::Convert.new(@options, 1000).execute("test agent", 1234)
    end

    it "adds a last-modified header" do
      result = Imageproxy::Convert.new(@options, 1000).execute("test agent", 1234)
      result.headers['Last-Modified'].should be_instance_of(String)
    end
  end

  context "When requesting a resize we already may have cached" do
    before do
      @options = mock("options")
      @options.stub(:resize).and_return("123x456")
      @options.stub(:source).and_return("http://example.com/sample.png")
      @options.stub(:shape).and_return(nil)
      @options.stub(:keys).and_return([:resize, :source])
      @options.stub(:[]).with(:resize).and_return("123x456")
      @options.stub(:[]).with(:source).and_return("http://example.com/sample.png")

      @response = mock("response")
      @response.stub(:headers).and_return({:etag => '"SOMEETAG"'})
      @response.stub(:code).and_return(200)
      RestClient.stub(:get).and_return(@response)
      @response.stub(:to_str).and_return(open('public/sample.png').read)
    end

    it "resizes the image if the source has changed" do
      RestClient.should_receive(:get).with("http://example.com/sample.png", :timeout => 1234, :user_agent => "test agent", :if_none_match => '"SOMEETAG"', :accept => '*/*').and_return(@response)

      result = Imageproxy::Convert.new(@options, 1000, '"SOMEETAG-foo"').execute("test agent", 1234)

      result.should be_modified
    end

    it "doesn't resize the image if source hasn't changed" do
      RestClient.stub(:get).and_raise(RestClient::NotModified.new(@response))
      RestClient.should_receive(:get).with("http://example.com/sample.png", :timeout => 1234, :user_agent => "test agent", :if_none_match => '"SOMEETAG"', :accept => '*/*').and_return(@response)
      Magick::Image.should_not_receive(:from_blob)

      result = Imageproxy::Convert.new(@options, 1000, '"SOMEETAG-foo"').execute("test agent", 1234)

      result.should_not be_modified
    end
  end
end
