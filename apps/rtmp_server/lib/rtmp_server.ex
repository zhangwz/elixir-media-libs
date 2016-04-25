defmodule RtmpServer do
  use Application
  
  def start(_type, _args) do
    import Supervisor.Spec, warn: false
       
    children = [
      worker(RtmpServer.Worker, [])
    ]
    
    opts = [strategy: :one_for_one, name: RtmpServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
  
  def recompile() do
    Mix.Task.reenable("app.start")
    Mix.Task.reenable("compile")
    Mix.Task.reenable("compile.all")
    compilers = Mix.compilers
    Enum.each compilers, &Mix.Task.reenable("compile.#{&1}")
    Mix.Task.run("compile.all")
  end  
end
