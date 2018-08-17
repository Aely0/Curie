defmodule Curie.Data.Leaderboard do
  use Ecto.Schema
  import Ecto.Changeset

  schema "leaderboard" do
    field(:channel_id, :integer)
    field(:message_id, :integer)
    field(:last_refresh, :string)
    field(:page_count, :integer)
    field(:current_page, :integer)
    field(:entries, {:array, :string})
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, [
      :channel_id,
      :message_id,
      :last_refresh,
      :page_count,
      :current_page,
      :entries
    ])
  end
end
