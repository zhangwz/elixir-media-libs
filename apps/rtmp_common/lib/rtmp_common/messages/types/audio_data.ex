defmodule RtmpCommon.Messages.Types.AudioData do
  @moduledoc """
  Data structure containing audio data
  """  
  
  @behaviour RtmpCommon.Messages.Message
  
  defstruct data: <<>>
  
  def parse(data) do
    %__MODULE__{data: data}
  end
  
  def serialize(%__MODULE__{data: data}) do    
    {:ok, %RtmpCommon.Messages.SerializedMessage{
      message_type_id: 8,
      data: data
    }} 
  end
  
  def get_default_chunk_stream_id(%__MODULE__{}),  do: 5
end