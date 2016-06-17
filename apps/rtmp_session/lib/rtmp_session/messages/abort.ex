defmodule RtmpSession.Messages.Abort do
  @moduledoc """
  
  Message used to notify the peer that if it is waiting
  for chunks to complete a message, then discard the partially
  received message
  
  """
  
  @behaviour RtmpSession.RtmpMessage
  @type t :: %__MODULE__{}
  
  defstruct stream_id: nil
  
  def parse(data) do
    <<stream_id::32>> = data
    
    %__MODULE__{stream_id: stream_id}
  end
  
  def serialize(message = %__MODULE__{}) do
    {:ok, %RtmpSession.RtmpMessage{
      message_type_id: 2,
      payload: <<message.stream_id::size(4)-unit(8)>>
    }}
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 2
end