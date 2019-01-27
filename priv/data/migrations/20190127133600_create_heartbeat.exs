defmodule Curie.Data.Migrations.CreateHeartbeat do
  use Ecto.Migration

  def change do
    create table("heartbeat", primary_key: false) do
      add(:heartbeat, :bigint, primary_key: true)
    end
  end
end
