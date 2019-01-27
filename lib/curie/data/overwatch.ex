defmodule Curie.Data.Overwatch do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          build: String.t(),
          tweet: String.t() | nil
        }

  @primary_key {:build, :string, []}
  schema "overwatch" do
    field(:tweet, :string)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, [:build, :tweet])
    |> validate_required([:build])
  end
end
