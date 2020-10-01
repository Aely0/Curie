defmodule Curie.Data do
  @moduledoc """
  Database component.
  """

  use Ecto.Repo,
    otp_app: :curie,
    adapter: Ecto.Adapters.Postgres
end
