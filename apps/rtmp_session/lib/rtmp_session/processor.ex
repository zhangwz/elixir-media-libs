defmodule RtmpSession.Processor do
  @moduledoc """
  The RTMP session processor represents the core finite state machine dictating
  how incoming RTMP messages should be handled, including determining what RTMP messages
  should be sent to the peer and what events the session needs to react to.
  """

  alias RtmpSession.DetailedMessage, as: DetailedMessage
  alias RtmpSession.Messages, as: MessageTypes
  alias RtmpSession.Events, as: Events
  alias RtmpSession.SessionConfig, as: SessionConfig

  require Logger

  @type handle_result :: {:response, DetailedMessage.t} | {:event, Events.t}

  defmodule State do
    defstruct current_stage: :started,
      peer_window_ack_size: nil,
      peer_bytes_received: 0,
      last_acknowledgement_sent_at: 0,
      configuration: nil,
      active_requests: %{},
      last_request_id: 0,
      connected_app_name: nil
  end

  @spec new(%SessionConfig{}) :: %State{}
  def new(config = %SessionConfig{}) do
    %State{
      configuration: config
    }
  end

  @spec notify_bytes_received(%State{}, non_neg_integer()) :: {%State{}, [handle_result]}
  def notify_bytes_received(state = %State{}, bytes_received) do
    state = %{state | peer_bytes_received: state.peer_bytes_received + bytes_received}
    bytes_since_last_ack = state.peer_bytes_received - state.last_acknowledgement_sent_at
    
    cond do
      state.peer_window_ack_size == nil ->
        {state, []}

      bytes_since_last_ack < state.peer_window_ack_size ->
        {state, []}

      true ->
        state = %{state | last_acknowledgement_sent_at: state.peer_bytes_received }
        ack_message = %MessageTypes.Acknowledgement{sequence_number: state.peer_bytes_received}
        results = [{:response, form_response_message(state, ack_message, 0)}]
        {state, results}
    end
  end

  @spec handle(%State{}, DetailedMessage.t) :: {%State{}, [handle_result]}
  def handle(state = %State{}, message = %DetailedMessage{}) do
    do_handle(state, message)
  end

  @spec accept_request(%State{}, non_neg_integer()) :: {%State{}, [handle_result]}
  def accept_request(state = %State{}, request_id) do
    request = Map.fetch!(state.active_requests, request_id)
    state = %{state | active_requests: Map.delete(state.active_requests, request_id)}

    case request do
      {:connect, app_name} -> accept_connect_request(state, app_name)
    end
  end

  defp do_handle(state, %DetailedMessage{content: %MessageTypes.SetChunkSize{size: size}}) do
    {state, [{:event, %Events.PeerChunkSizeChanged{new_chunk_size: size}}]}
  end

  defp do_handle(state, %DetailedMessage{content: %MessageTypes.WindowAcknowledgementSize{size: size}}) do
    state = %{state | peer_window_ack_size: size}
    {state, []}
  end

  defp do_handle(state, message = %DetailedMessage{content: %MessageTypes.Amf0Command{}}) do
    handle_command(state, 
                   message.stream_id, 
                   message.content.command_name, 
                   message.content.transaction_id, 
                   message.content.command_object,
                   message.content.additional_values)
  end

  defp do_handle(state, message = %DetailedMessage{content: %{__struct__: message_type}}) do
    simple_name = String.replace(to_string(message_type), "Elixir.RtmpSession.Messages.", "")

    _ = Logger.info "Unable to handle #{simple_name} message on stream id #{message.stream_id}"
    {state, []}
  end
  
  defp form_response_message(_state, message_content, stream_id) do
    %DetailedMessage{
      stream_id: stream_id,
      content: message_content
    }
  end

  defp handle_command(state = %State{current_stage: :started}, _stream_id, "connect", _transaction_id, command_obj, _args) do
    _ = Logger.debug "Connect command received"

    app_name = command_obj["app"]
    request_id = state.last_request_id + 1
    request = {:connect, app_name}
    state = %{state | 
      last_request_id: request_id,
      active_requests: Map.put(state.active_requests, request_id, request)
    }

    responses = [
      {:response, %DetailedMessage{
        stream_id: 0,
        timestamp: 0, 
        content: %MessageTypes.SetPeerBandwidth{window_size: state.configuration.peer_bandwidth, limit_type: :hard}
      }},
      {:response, %DetailedMessage{
        timestamp: 0,
        stream_id: 0,
        content: %MessageTypes.WindowAcknowledgementSize{size: state.configuration.window_ack_size}
      }},
      {:response, %DetailedMessage{
        timestamp: 0,
        stream_id: 0,
        content: %MessageTypes.SetChunkSize{size: state.configuration.chunk_size}
      }},
      {:response, %DetailedMessage{
        timestamp: 0,
        stream_id: 0,
        content: %MessageTypes.UserControl{type: :stream_begin, stream_id: 0}
      }}
    ]

    events = [
      {:event, %Events.ConnectionRequested{
        request_id: request_id,
        app_name: app_name
      }}
    ]

    {state, responses ++ events}
  end

  defp handle_command(state, stream_id, command_name, _transaction_id, _command_obj, _args) do
    _ = Logger.info "Unable to handle command '#{command_name}' from stream id #{stream_id} in stage #{state.current_stage}"
    {state, []}
  end

  defp accept_connect_request(state, application_name) do
    state = %{state |
      current_stage: :connected,
      connected_app_name: application_name 
    }

    response = {:response, %DetailedMessage{
      timestamp: 0,
      stream_id: 0,
      content: %MessageTypes.Amf0Command{
        command_name: "_result",
        transaction_id: 1,
        command_object: %{
          "fmsVer" => state.configuration.fms_version,
          "capabilities" => 31
        },
        additional_values: [%{
          "level" => "status",
          "code" => "NetConnection.Connect.Success",
          "description" => "Connection succeeded",
          "objectEncoding" => 0
        }]
      }
    }}

    {state, [response]}
  end
end