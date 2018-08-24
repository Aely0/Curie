defmodule Curie.Data.Migrations.CreateBalance do
  use Ecto.Migration

  def change do
    create table("balance", primary_key: false) do
      add(:member, :bigint, primary_key: true)
      add(:value, :integer)
      add(:guild, :bigint)
    end
  end
end
