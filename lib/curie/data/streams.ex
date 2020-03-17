defmodule Curie.Data.Streams do
  use Ecto.Schema
  import Ecto.Changeset
  alias Nostrum.Snowflake

  @type t :: %__MODULE__{
          member: Snowflake.t(),
          time: pos_integer
        }

  @primary_key {:member, :integer, []}
  schema "streams" do
    field(:time, :integer)
    field(:channel_id, :integer)
    field(:message_id, :integer)
  end

  @spec changeset(%__MODULE__{}, map) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, [:member, :time, :channel_id, :message_id])
    |> validate_required([:member, :time, :channel_id, :message_id])
  end
end
