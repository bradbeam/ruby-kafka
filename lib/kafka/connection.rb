require "socket"
require "kafka/protocol/request_message"
require "kafka/protocol/encoder"
require "kafka/protocol/decoder"

module Kafka

  # A connection to a single Kafka broker.
  #
  # Usually you'll need a separate connection to each broker in a cluster, since most
  # requests must be directed specifically to the broker that is currently leader for
  # the set of topic partitions you want to produce to or consumer from.
  class Connection

    # Opens a connection to a Kafka broker.
    #
    # @param host [String] the hostname of the broker.
    # @param port [Integer] the port of the broker.
    # @param client_id [String] the client id is a user-specified string sent in each
    #   request to help trace calls and should logically identify the application
    #   making the request.
    # @param logger [Logger] the logger used to log trace messages.
    #
    # @return [Connection] a new connection.
    def self.open(host:, port:, client_id:, logger:)
      logger.info "Opening connection to #{host}:#{port} with client id #{client_id}..."

      socket = TCPSocket.new(host, port)
      new(socket: socket, client_id: client_id, logger: logger)
    rescue SocketError => e
      logger.error "Failed to connect to #{host}:#{port}: #{e}"

      raise ConnectionError, e
    end

    def initialize(socket:, client_id:, logger:)
      @client_id = client_id
      @logger = logger
      @socket = socket
      @encoder = Kafka::Protocol::Encoder.new(@socket)
      @decoder = Kafka::Protocol::Decoder.new(@socket)
      @correlation_id = 0
    end

    # Writes a request over the connection.
    #
    # @param api_key [Integer] the integer code for the API that is invoked.
    # @param request [#encode] the request that should be encoded and written.
    #
    # @return [nil]
    def write_request(api_key, request)
      @correlation_id += 1

      message = Kafka::Protocol::RequestMessage.new(
        api_key: api_key,
        api_version: 0,
        correlation_id: @correlation_id,
        client_id: @client_id,
        request: request,
      )

      buffer = StringIO.new
      message_encoder = Kafka::Protocol::Encoder.new(buffer)
      message.encode(message_encoder)

      @logger.info "Sending request #{@correlation_id} (#{request.class})..."

      @encoder.write_bytes(buffer.string)

      nil
    end

    # Reads a response from the connection.
    #
    # @param response [#decode] an empty response object that can decode the
    #   response bytes.
    #
    # @return [nil]
    def read_response(response)
      @logger.info "Reading response #{response.class}"

      bytes = @decoder.bytes

      buffer = StringIO.new(bytes)
      response_decoder = Kafka::Protocol::Decoder.new(buffer)

      correlation_id = response_decoder.int32

      @logger.info "Correlation id #{correlation_id}"

      response.decode(response_decoder)

      nil
    end
  end
end