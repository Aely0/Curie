defmodule Curie.Data.Migrations.CreateDetails do
  use Ecto.Migration

  def change do
    create table("details", primary_key: false) do
      add(:member, :bigint, primary_key: true)
      add(:offline_since, :bigint)
      add(:last_status_change, :bigint)
      add(:last_status_type, :text)
      add(:spoke, :bigint)
      add(:guild_id, :bigint)
      add(:channel, :text)
    end
  end
end
