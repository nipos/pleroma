defmodule Pleroma.Repo.Migrations.CreatePleroma.User do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string
      add :password_hash, :string
      add :name, :string
      add :nickname, :string
      add :bio, :string

      timestamps()
    end

  end
end
