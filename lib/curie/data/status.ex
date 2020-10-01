defmodule Curie.Data.Status do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          message: String.t(),
          member: String.t()
        }

  @primary_key {:message, :string, []}
  schema "status" do
    field(:member, :string)
  end

  @spec changeset(%__MODULE__{}, map) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, [:message, :member])
    |> validate_required([:message, :member])
  end
end
