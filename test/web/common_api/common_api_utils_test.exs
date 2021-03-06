defmodule Pleroma.Web.CommonAPI.UtilsTest do
  alias Pleroma.Web.CommonAPI.Utils
  alias Pleroma.Builders.{UserBuilder}
  use Pleroma.DataCase

  test "it adds attachment links to a given text and attachment set" do
    name =
      "Sakura%20Mana%20%E2%80%93%20Turned%20on%20by%20a%20Senior%20OL%20with%20a%20Temptating%20Tight%20Skirt-s%20Full%20Hipline%20and%20Panty%20Shot-%20Beautiful%20Thick%20Thighs-%20and%20Erotic%20Ass-%20-2015-%20--%20Oppaitime%208-28-2017%206-50-33%20PM.png"

    attachment = %{
      "url" => [%{"href" => name}]
    }

    res = Utils.add_attachments("", [attachment])

    assert res ==
             "<br><a href=\"#{name}\" class='attachment'>Sakura Mana – Turned on by a Se…</a>"
  end

  describe "it confirms the password given is the current users password" do
    test "incorrect password given" do
      {:ok, user} = UserBuilder.insert()

      assert Utils.confirm_current_password(user, %{"password" => ""}) ==
               {:error, "Invalid password."}
    end

    test "correct password given" do
      {:ok, user} = UserBuilder.insert()
      assert Utils.confirm_current_password(user, %{"password" => "test"}) == {:ok, user}
    end
  end
end
