defmodule Curie.Data.Migrations.CreateHelp do
  use Ecto.Migration

  def change do
    create table("help", primary_key: false) do
      add(:command, :text, primary_key: true)
      add(:description, :text)
      add(:short, :text)
    end
  end
end
