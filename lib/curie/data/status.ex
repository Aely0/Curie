defmodule Curie.Data.Status do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:message, :string, []}
  schema "status" do
    field(:member, :string)
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:message, :member])
    |> validate_required([:message, :member])
  end
end
