defmodule Curie.Data.Migrations.CreateStreams do
  use Ecto.Migration

  def change do
    create table("streams", primary_key: false) do
      add(:member, :bigint, primary_key: true)
      add(:time, :bigint)
    end
  end
end
