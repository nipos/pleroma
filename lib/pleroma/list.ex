defmodule Pleroma.List do
  use Ecto.Schema
  import Ecto.{Changeset, Query}
  alias Pleroma.User

  schema "lists" do
    belongs_to(:user, Pleroma.User)
    field(:title, :string)
    field(:following, {:array, :string}, default: [])

    timestamps()
  end

  @doc false
  def changeset(list, attrs) do
    list
    |> cast(attrs, [:title])
    |> validate_required([:title])
  end

  def for_user(user, opts) do
    query =
      from(
        l in Pleroma.List,
        where: l.user_id == ^user.id,
        order_by: [desc: l.id],
        limit: 50
      )

    Repo.all(query)
  end

  def get(%{id: user_id} = _user, id) do
    query =
      from(
        l in Pleroma.List,
        where: l.id == ^id,
        where: l.user_id == ^user_id
      )

    Repo.one(query)
  end

  def rename(%Pleroma.List{} = list, title) do
    update_list(list, %{title: title})
  end

  # TODO check that user is following followed
  def follow(%Pleroma.List{following: following} = list, %User{} = followed) do
    update_list(list, %{following: Enum.uniq([followed.follower_address | following])})
  end

  def unfollow(%Pleroma.List{following: following} = list, %User{} = unfollowed) do
    update_list(list, %{following: List.delete(following, unfollowed.follower_address)})
  end

  def delete(%Pleroma.List{} = list) do
    Repo.delete(list)
  end

  def update_list(%Pleroma.List{} = list, attrs) do
    list
    |> changeset(attrs)
    |> Repo.update()
  end
end
