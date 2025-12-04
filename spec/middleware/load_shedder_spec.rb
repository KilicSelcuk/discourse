# frozen_string_literal: true

require "rack/mock"

class FakeSocket
  attr_reader :writes

  def initialize(responses)
    @responses = responses
    @writes = []
  end

  def write(str)
    @writes << str
  end

  def gets
    @responses.shift
  end

  def close
  end
end

RSpec.describe LoadShedder::Middleware do
  let(:app) { ->(_env) { [200, { "X-Runtime" => "0.01" }, ["ok"]] } }
  let(:client) { instance_spy(LoadShedder::Client) }

  before { ENV["DISCOURSE_LOAD_SHEDDER_ENABLED"] = "true" }

  def call_with_sockets(response_lines, headers: {}, path: "/")
    allow(client).to receive(:admit).and_return(response_lines)
    allow(client).to receive(:complete)
    env = Rack::MockRequest.env_for(path, headers)
    described_class.new(app, client: client).call(env)
  end

  it "returns 503 when daemon rejects anon requests" do
    status, headers, body =
      call_with_sockets({ admitted: false, limit: 2, inflight: 2, degraded: 1, contacted: true })

    expect(status).to eq(503)
    expect(headers["Retry-After"]).to eq("2")
    expect(headers["X-AC-Limit"]).to eq("2")
    expect(headers["X-AC-Inflight"]).to eq("2")
    expect(headers["X-AC-Degraded"]).to eq("1")
    expect(body.join).to eq(I18n.t("load_shedder.server_busy"))
  end

  it "allows logged-in requests even when daemon rejects" do
    allow(Auth::DefaultCurrentUserProvider).to receive(:find_v1_auth_cookie).and_return("t")
    allow(client).to receive(:admit).and_return(
      admitted: false,
      limit: 2,
      inflight: 2,
      degraded: 1,
      contacted: true,
    )
    allow(client).to receive(:complete)

    status, headers, _body =
      described_class.new(app, client: client).call(Rack::MockRequest.env_for("/"))

    expect(status).to eq(200)
    expect(headers["X-AC-Degraded"]).to eq("1")
    expect(client).to have_received(:admit).with("user")
  end

  it "fails open when daemon is unavailable" do
    allow(client).to receive(:admit).and_raise(Errno::ENOENT)
    status, = described_class.new(app, client: client).call(Rack::MockRequest.env_for("/"))

    expect(status).to eq(200)
  end

  it "flags message-bus long polls as unsampled" do
    allow(client).to receive(:admit).and_return(
      admitted: true,
      limit: 3,
      inflight: 1,
      degraded: 0,
      contacted: true,
    )
    allow(client).to receive(:complete)

    described_class.new(app, client: client).call(Rack::MockRequest.env_for("/message-bus/poll"))

    expect(client).to have_received(:complete).with(
      kind: "anon",
      status: 200,
      rtt_ms: 10,
      sampled: false,
    )
  end
end
