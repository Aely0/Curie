defmodule Curie.Data.Leaderboard do
  use Curie.Data.Schema

  schema "leaderboard" do
    field(:channel_id, :integer)
    field(:message_id, :integer)
    field(:last_refresh, :string)
    field(:page_count, :integer)
    field(:current_page, :integer)
    field(:entries, :string)
  end

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
