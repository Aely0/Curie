defmodule Curie.Data.Balance do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:member, :integer, []}
  schema "balance" do
    field(:value, :integer)
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:member, :value])
    |> validate_required([:member])
  end
end
