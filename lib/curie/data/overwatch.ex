defmodule Curie.Data.Overwatch do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:build, :string, []}
  schema "overwatch" do
    field(:tweet, :string)
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:build, :tweet])
    |> validate_required([:build])
  end
end
