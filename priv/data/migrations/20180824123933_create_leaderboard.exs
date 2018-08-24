defmodule Curie.Data.Migrations.CreateLeaderboard do
  use Ecto.Migration

  def change do
    create table("leaderboard", primary_key: false) do
      add(:channel_id, :bigint, primary_key: true)
      add(:message_id, :bigint)
      add(:last_refresh, :text)
      add(:page_count, :integer)
      add(:current_page, :integer)
      add(:entries, {:array, :text})
    end
  end
end
