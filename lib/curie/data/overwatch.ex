defmodule Curie.Data.Overwatch do
  use Curie.Data.Schema

  @primary_key {:date, :string, []}
  schema "overwatch", do: nil

  def changeset(struct, params) do
    struct
    |> cast(params, [:date])
    |> validate_required([:date])
  end
end
