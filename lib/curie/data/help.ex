defmodule Curie.Data.Help do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          command: String.t(),
          description: String.t(),
          short: String.t() | nil
        }

  @primary_key {:command, :string, []}
  schema "help" do
    field(:description, :string)
    field(:short, :string)
  end

  @spec changeset(%__MODULE__{}, map) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, [:command, :description, :short])
    |> validate_required([:command, :description])
  end
end
