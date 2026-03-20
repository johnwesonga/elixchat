defmodule MyChatApp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyChatAppWeb.Telemetry,
      MyChatApp.Repo,
      {DNSCluster, query: Application.get_env(:my_chat_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MyChatApp.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: MyChatApp.Finch},
      # Start a worker by calling: MyChatApp.Worker.start_link(arg)
      # {MyChatApp.Worker, arg},
      # Start to serve requests, typically the last entry
      MyChatAppWeb.Endpoint,
      MyChatApp.Chat.Presence,
      {Registry, keys: :unique, name: MyChatApp.Chat.Registry},
      {DynamicSupervisor, name: MyChatApp.Chat.RoomSupervisor, strategy: :one_for_one},
      MyChatApp.Chat.RoomManager
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MyChatApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MyChatAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
