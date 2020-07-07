defmodule Curie.Data do
  use Ecto.Repo,
    otp_app: :curie,
    adapter: Ecto.Adapters.Postgres
end
