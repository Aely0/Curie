defmodule Curie.Data.Details do
  use Ecto.Schema
  import Ecto.Changeset
  alias Nostrum.Struct.Snowflake

  @type t :: %__MODULE__{
          member: Snowflake.t(),
          offline_since: pos_integer() | nil,
          last_status_change: pos_integer() | nil,
          last_status_type: String | nil,
          spoke: pos_integer() | nil,
          guild_id: Snowflake.t() | nil,
          channel: String.t() | nil
        }

  @primary_key {:member, :integer, []}
  schema "details" do
    field(:offline_since, :integer)
    field(:last_status_change, :integer)
    field(:last_status_type, :string)
    field(:spoke, :integer)
    field(:guild_id, :integer)
    field(:channel, :string)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, [
      :member,
      :offline_since,
      :last_status_change,
      :last_status_type,
      :spoke,
      :guild_id,
      :channel
    ])
    |> validate_required([:member])
  end
end
