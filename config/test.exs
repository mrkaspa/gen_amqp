use Mix.Config

config :gen_amqp,
  amqp_url: System.get_env("RABBITCONN") || "amqp://guest:guest@localhost",
  conn_name: ConnHub,
  static_sup_name: StaticConnSup,
  dynamic_sup_name: DynamicConnSup,
  error_handler: ErrorHandler
