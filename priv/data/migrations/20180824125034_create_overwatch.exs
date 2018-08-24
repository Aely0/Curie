defmodule Curie.Data.Migrations.CreateOverwatch do
  use Ecto.Migration

  def change do
    create table("overwatch", primary_key: false) do
      add(:build, :text, primary_key: true)
      add(:tweet, :text)
    end
  end
end
