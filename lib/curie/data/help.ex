defmodule Curie.Data.Help do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:command, :string, []}
  schema "help" do
    field(:description, :string)
    field(:short, :string)
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:command, :description, :short])
    |> validate_required([:command, :description])
  end
end
