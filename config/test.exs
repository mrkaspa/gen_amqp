use Mix.Config

config :gen_amqp,
  connections: [
    {:static, StaticConnSup, ConnHub,
     System.get_env("RABBITCONN") || "amqp://guest:guest@localhost"},
    {:dynamic, DynamicConnSup, System.get_env("RABBITCONN") || "amqp://guest:guest@localhost"}
  ],
  error_handler: ErrorHandler
