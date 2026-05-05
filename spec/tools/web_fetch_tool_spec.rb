# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebFetchTool do
  subject(:tool) { described_class.new(chat: instance_double("Chat")) }

  describe "#execute" do
    it "blocks private DNS results before opening a connection" do
      allow(Socket).to receive(:getaddrinfo).and_return([
        [ "AF_INET", 80, "localhost", "127.0.0.1" ]
      ])

      expect(Net::HTTP).not_to receive(:new)

      result = tool.execute(url: "http://example.com")

      expect(result[:error]).to include("private/internal networks")
    end

    it "blocks hosts when any resolved address is private" do
      allow(Socket).to receive(:getaddrinfo).and_return([
        [ "AF_INET", 80, "example.com", "93.184.216.34" ],
        [ "AF_INET", 80, "localhost", "127.0.0.1" ]
      ])

      expect(Net::HTTP).not_to receive(:new)

      result = tool.execute(url: "http://example.com")

      expect(result[:error]).to include("private/internal networks")
    end

    it "connects to the validated IP while keeping the URL host on the HTTP client" do
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@read, true)
      response.body = "<html><body>Hello from the public web</body></html>"
      response["content-type"] = "text/html"

      http = instance_double(Net::HTTP)
      allow(http).to receive(:ipaddr=).with("93.184.216.34")
      allow(http).to receive(:use_ssl=).with(true)
      allow(http).to receive(:open_timeout=).with(WebFetchTool::REQUEST_TIMEOUT)
      allow(http).to receive(:read_timeout=).with(WebFetchTool::REQUEST_TIMEOUT)
      allow(http).to receive(:request).and_return(response)

      allow(Socket).to receive(:getaddrinfo).and_return([
        [ "AF_INET", 443, "example.com", "93.184.216.34" ]
      ])
      expect(Net::HTTP).to receive(:new).with("example.com", 443).and_return(http)

      result = tool.execute(url: "https://example.com/page")

      expect(result).to include("Hello from the public web")
    end
  end
end
