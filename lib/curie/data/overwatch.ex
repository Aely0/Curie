defmodule Curie.Data.Overwatch do
  use Curie.Data.Schema

  @primary_key {:build, :string, []}
  schema "overwatch", do: nil

  def changeset(struct, params) do
    struct
    |> cast(params, [:build])
    |> validate_required([:build])
  end
end
