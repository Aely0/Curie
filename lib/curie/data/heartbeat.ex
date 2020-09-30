defmodule Curie.Data.Heartbeat do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{heartbeat: pos_integer}

  @primary_key {:heartbeat, :integer, []}
  schema("heartbeat", do: [])

  @spec changeset(%__MODULE__{}, map) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, [:heartbeat])
    |> validate_required([:heartbeat])
  end
end
