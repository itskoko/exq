defmodule Exq.Support.Opts do

  alias Exq.Support.Coercion
  alias Exq.Support.Config

  @doc """
   Return top supervisor's name default is Exq.Sup
  """
  def top_supervisor(name) do
    name = name || Config.get(:name)
    "#{name}.Sup" |> String.to_atom
  end

  defp conform_opts(opts) do
    mode = opts[:mode] || Config.get(:mode)
    redis = redis_client_name(opts[:name])
    opts = [{:redis, redis}|opts]

    redis_opts = redis_opts(opts)
    connection_opts = connection_opts(opts)
    server_opts = server_opts(mode, opts)
    {redis_opts, connection_opts, server_opts}
  end

  def redis_client_name(name) do
    name = name || Config.get(:name)
    "#{name}.Redis.Client" |> String.to_atom
  end

  def redis_opts(opts \\ []) do
    if url = opts[:url] || Config.get(:url) do
      url
    else
      host = opts[:host] || Config.get(:host)
      port = Coercion.to_integer(opts[:port] || Config.get(:port))
      database = Coercion.to_integer(opts[:database] || Config.get(:database))
      password = opts[:password] || Config.get(:password)
      [host: host, port: port, database: database, password: password]
    end
  end

  @doc """
   Return {redis_module, redis_args, gen_server_opts}
  """
  def redis_worker_opts(opts) do
    {redis_opts, connection_opts, opts} = conform_opts(opts)
    case Config.get(:redis_worker) do
      {module, args} -> {module, args, opts}
      _ -> {Redix, [redis_opts, connection_opts], opts}
    end
  end

  def redis_worker_module() do
    case Config.get(:redis_worker) do
      {module, _args} -> module
      _ -> Redix
    end
  end

  def connection_opts(opts \\ []) do
    reconnect_on_sleep = opts[:reconnect_on_sleep] || Config.get(:reconnect_on_sleep)
    timeout = opts[:redis_timeout] || Config.get(:redis_timeout)
    socket_opts = opts[:socket_opts] || Config.get(:socket_opts) || []

    [backoff: reconnect_on_sleep, timeout: timeout, name: opts[:redis], socket_opts: socket_opts]
  end

  defp server_opts(:default, opts) do
    scheduler_enable = opt_or_config(opts, :scheduler_enable)
    stats_enable = opt_or_config(opts, :stats_enable)

    namespace = opt_or_config(opts, :namespace)
    scheduler_poll_timeout = opt_or_config(opts, :scheduler_poll_timeout)
    poll_timeout = opt_or_config(opts, :poll_timeout)
    shutdown_timeout = opt_or_config(opts, :shutdown_timeout)

    enqueuer = Exq.Enqueuer.Server.server_name(opts[:name])
    stats = Exq.Stats.Server.server_name(opts[:name])
    scheduler = Exq.Scheduler.Server.server_name(opts[:name])
    workers_sup = Exq.Worker.Supervisor.supervisor_name(opts[:name])
    middleware = Exq.Middleware.Server.server_name(opts[:name])
    metadata = Exq.Worker.Metadata.server_name(opts[:name])

    queue_configs = opt_or_config(opts, :queues)
    per_queue_concurrency = opt_or_config(opts, :concurrency)
    queues = get_queues(queue_configs)
    concurrency = get_concurrency(queue_configs, per_queue_concurrency)
    default_middleware = Config.get(:middleware)

    [scheduler_enable: scheduler_enable, stats_enable: stats_enable, namespace: namespace,
     scheduler_poll_timeout: scheduler_poll_timeout,workers_sup: workers_sup,
     poll_timeout: poll_timeout, enqueuer: enqueuer, metadata: metadata,
     stats: stats, name: opts[:name], scheduler: scheduler, queues:
     queues, redis: opts[:redis], concurrency: concurrency,
     middleware: middleware, default_middleware: default_middleware,
     mode: :default, shutdown_timeout: shutdown_timeout]
  end
  defp server_opts(mode, opts) do
    namespace = opt_or_config(opts, :namespace)
    [name: opts[:name], namespace: namespace, redis: opts[:redis], mode: mode]
  end

  defp opt_or_config(opts, key) do
    case opts[key] do
      nil ->
        Config.get(key)
      opt ->
        opt
    end
  end

  defp get_queues(queue_configs) do
    Enum.map(queue_configs, fn queue_config ->
      case queue_config do
        {queue, _concurrency} -> queue
        queue -> queue
      end
    end)
  end

  defp get_concurrency(queue_configs, per_queue_concurrency) do
    Enum.map(queue_configs, fn (queue_config) ->
        case queue_config do
          {queue, concurrency} -> {queue, concurrency, 0}
          queue -> {queue, per_queue_concurrency, 0}
        end
    end)
  end

end
