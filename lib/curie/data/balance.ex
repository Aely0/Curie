defmodule Curie.Data.Balance do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  alias Nostrum.Snowflake

  @type t :: %__MODULE__{
          member: Snowflake.t(),
          value: pos_integer,
          guild: Snowflake.t()
        }

  @primary_key {:member, :integer, []}
  schema "balance" do
    field(:value, :integer)
    field(:guild, :integer)
  end

  @spec changeset(%__MODULE__{}, map) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, [:member, :value, :guild])
    |> validate_required([:member])
  end
end
