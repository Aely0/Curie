defmodule Curie.Data.Leaderboard do
  use Ecto.Schema
  import Ecto.Changeset
  alias Nostrum.Struct.Snowflake

  @type t :: %__MODULE__{
          channel_id: Snowflake.t(),
          guild_id: Snowflake.t(),
          message_id: Snowflake.t(),
          last_refresh: pos_integer(),
          page_count: pos_integer(),
          current_page: pos_integer(),
          entries: [String.t()]
        }

  @primary_key {:channel_id, :integer, []}
  schema "leaderboard" do
    field(:guild_id, :integer)
    field(:message_id, :integer)
    field(:last_refresh, :string)
    field(:page_count, :integer)
    field(:current_page, :integer)
    field(:entries, {:array, :string})
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, [
      :channel_id,
      :guild_id,
      :message_id,
      :last_refresh,
      :page_count,
      :current_page,
      :entries
    ])
  end
end
