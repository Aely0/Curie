defmodule Curie.Data.Migrations.CreateDetails do
  use Ecto.Migration

  def change do
    create table("details", primary_key: false) do
      add(:member, :bigint, primary_key: true)
      add(:online, :bigint)
      add(:spoke, :bigint)
      add(:channel, :text)
    end
  end
end
