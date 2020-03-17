# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :nostrum,
  token: "DISCORD_API_TOKEN",
  num_shards: :auto

config :curie,
  tempest: "<:tempest:408292279154114570>",
  owner: 90_575_330_862_972_928,
  prefix: "!",
  stream_message_cooldown: 21600

config :curie,
  darkskies: "DARKSKIES_TOKEN",
  googlemaps: "GOOGLEMAPS_TOKEN",
  twitch: "TWITCH_TOKEN",
  twitter: "TWITTER_TOKEN"

config :curie,
  channels: %{
    general: 99_304_946_280_701_952,
    overwatch: 169_835_616_110_903_307,
    invisible: 141_160_537_672_122_368,
    logs: 564_656_170_304_798_740
  }

config :curie,
  colors: %{
    "green" => 0x13A324,
    "red" => 0xB21A1A,
    "lblue" => 0x193C4,
    "dblue" => 0xB3F93,
    "yellow" => 0xFFC107,
    "purple" => 0x6441A5,
    "white" => 0xFFFFFE
  },
  color_roles: %{
    "Haunted" => 165_474_974_092_623_873,
    "Arcana" => 165_475_098_038_370_304,
    "Venom" => 255_997_278_794_416_129,
    "Heavenly" => 183_971_559_889_829_888,
    "Frozen" => 165_475_149_901_070_336,
    "Mist" => 255_997_694_483_496_960,
    "Malachite" => 255_999_090_163_318_784,
    "Infused" => 162_574_306_050_703_361,
    "Classified" => 165_475_205_584_519_168,
    "Immortal" => 162_574_042_803_601_408,
    "Legendary" => 165_475_377_374_953_472,
    "Ancient" => 165_475_436_854_378_496,
    "Corundum" => 255_999_965_854_171_136,
    "Corrupted" => 183_971_950_928_855_050,
    "Vintage" => 255_998_367_195_201_537,
    "snowflakes" => 371_732_667_080_638_466
  },
  roles: %{
    "felweed" => %{
      id: 104_219_404_408_995_840,
      mod_role_id: 563_800_515_805_184_062
    },
    "rally" => %{
      id: 291_690_851_422_175_232,
      mod_role_id: 563_800_522_352_754_699
    }
  }

config :curie, ecto_repos: [Curie.Data]

config :curie, Curie.Data,
  adapter: Ecto.Adapters.Postgres,
  hostname: "HOSTNAME",
  username: "USERNAME",
  password: "PASSWORD",
  database: "DATABASE",
  pool_size: 4

config :logger,
  backends: [:console, {LoggerFileBackend, :logfile}]

config :logger, :console,
  format: "\n$date $time $metadata[$level] $message\n",
  level: :warn

config :logger, :logfile,
  format: "\n$date $time $metadata[$level] $message\n",
  path: "LOGFILE_PATH",
  level: :info

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :curie, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:curie, :key)
#
# You can also configure a 3rd-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
import_config "#{Mix.env()}.exs"
