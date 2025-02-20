import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ex_term, ExTermWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "JF508wY58zm85QD5zUDQffsi91vvxJ9K+RY2SLfI7n3TZk5ITte042COtDpb/oRg",
  server: true

config :ex_term, :io_server, IEx.Server.Mock

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
