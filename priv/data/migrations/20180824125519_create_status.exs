defmodule Curie.Data.Migrations.CreateStatus do
  use Ecto.Migration

  def change do
    create table("status", primary_key: false) do
      add(:message, :text, primary_key: true)
      add(:member, :text)
    end
  end
end
