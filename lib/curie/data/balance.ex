defmodule Curie.Data.Balance do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:member, :integer, []}
  schema "balance" do
    field(:value, :integer)
    field(:guild, :integer)
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:member, :value, :guild])
    |> validate_required([:member])
  end
end
