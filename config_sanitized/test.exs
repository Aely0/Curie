use Mix.Config

config :nostrum,
  token: "<removed>",
  num_shards: :auto

config :curie,
  tempest: "<:tempest:473539185605869578>"

config :curie,
  channels: %{
    general: 473_537_127_116_963_841,
    overwatch: 473_537_127_116_963_841,
    invisible: 473_537_127_116_963_841
  }

config :curie,
  color_roles: %{
    "Legendary" => 487_301_163_864_293_397,
    "snowflakes" => 487_305_945_639_288_834
  }

config :curie, Curie.Data,
  adapter: Ecto.Adapters.Postgres,
  hostname: "<removed>",
  username: "<removed>",
  password: "<removed>",
  database: "<removed>"
