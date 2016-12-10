defmodule RtmpHandshake do
  @moduledoc """
  Provides functionality to handle the RTMP handshake process
  """

  require Logger

  alias RtmpHandshake.OldHandshakeFormat, as: OldHandshakeFormat
  alias RtmpHandshake.ParseResult, as: ParseResult
  alias RtmpHandshake.HandshakeResult, as: HandshakeResult

  @type handshake_type :: :unknown | :old
  @type is_valid_format_result :: :yes | :no | :unknown
  @type start_time :: non_neg_integer
  @type remaining_binary :: <<>>
  @type binary_response :: <<>>
  @type behaviour_state :: any
  @type process_result :: {:success, start_time, binary_response, remaining_binary}
                          | {:incomplete, binary_response}
                          | :failure


  @callback is_valid_format(<<>>) :: is_valid_format_result
  @callback process_bytes(behaviour_state, <<>>) :: {behaviour_state, process_result}
  @callback create_p0_and_p1_to_send(behaviour_state) :: {behaviour_state, <<>>}

  defmodule State do
    defstruct status: :pending,
              handshake_state: nil,
              handshake_type: :unknown,
              remaining_binary: <<>>,
              peer_start_timestamp: nil
  end

  @doc """
  Creates a new finite state machine to handle the handshake process,
    and preliminary parse results, including the initial x0 and x1
    binary to send to the peer.
  """
  @spec new() :: {%State{}, ParseResult.t}
  def new() do
    {handshake_state, bytes_to_send} =
      OldHandshakeFormat.new()
      |> OldHandshakeFormat.create_p0_and_p1_to_send()

    state = %State{handshake_type: :old, handshake_state: handshake_state}
    result = %ParseResult{current_state: :waiting_for_data, bytes_to_send: bytes_to_send}
    {state, result}
  end

  @doc "Reads the passed in binary to proceed with the handshaking process"
  @spec process_bytes(%State{}, <<>>) :: {%State{}, ParseResult.t}
  def process_bytes(state = %State{}, binary) when is_binary(binary) do
    case OldHandshakeFormat.process_bytes(state.handshake_state, binary) do
      {handshake_state, :failure} ->
        state = %{state | handshake_state: handshake_state}
        {state, %ParseResult{current_state: :failure}}

      {handshake_state, {:incomplete, bytes_to_send}} ->
        state = %{state | handshake_state: handshake_state}
        {state, %ParseResult{current_state: :waiting_for_data, bytes_to_send: bytes_to_send}}

      {handshake_state, {:success, start_time, response, remaining_binary}} ->
        state = %{state |
          handshake_state: handshake_state,
          remaining_binary: remaining_binary,
          peer_start_timestamp: start_time,
          status: :complete
        }

        result = %ParseResult{current_state: :success, bytes_to_send: response}
        {state, result}
    end
  end

  @doc """
  After a handshake has been successfully completed it is called to 
    retrieve the peer's starting timestamp and any left over binary that
    may need to be parsed later (not part of the handshake but instead part
    of the rtmp protocol).
  """
  @spec get_handshake_result(%State{}) :: {%State{}, HandshakeResult.t}
  def get_handshake_result(state = %State{status: :complete}) do
    unparsed_binary = state.remaining_binary
    
    {
      %{state | remaining_binary: <<>>},
      %HandshakeResult{
        peer_start_timestamp: state.peer_start_timestamp, 
        remaining_binary: unparsed_binary
      }
    }
  end

end
