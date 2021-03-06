defmodule Pleroma.Web.OStatus.ActivityRepresenter do
  alias Pleroma.{Activity, User, Object}
  alias Pleroma.Web.OStatus.UserRepresenter
  require Logger

  defp get_href(id) do
    with %Object{data: %{"external_url" => external_url}} <- Object.get_cached_by_ap_id(id) do
      external_url
    else
      _e -> id
    end
  end

  defp get_in_reply_to(%{"object" => %{"inReplyTo" => in_reply_to}}) do
    [
      {:"thr:in-reply-to",
       [ref: to_charlist(in_reply_to), href: to_charlist(get_href(in_reply_to))], []}
    ]
  end

  defp get_in_reply_to(_), do: []

  defp get_mentions(to) do
    Enum.map(to, fn id ->
      cond do
        # Special handling for the AP/Ostatus public collections
        "https://www.w3.org/ns/activitystreams#Public" == id ->
          {:link,
           [
             rel: "mentioned",
             "ostatus:object-type": "http://activitystrea.ms/schema/1.0/collection",
             href: "http://activityschema.org/collection/public"
           ], []}

        # Ostatus doesn't handle follower collections, ignore these.
        Regex.match?(~r/^#{Pleroma.Web.base_url()}.+followers$/, id) ->
          []

        true ->
          {:link,
           [
             rel: "mentioned",
             "ostatus:object-type": "http://activitystrea.ms/schema/1.0/person",
             href: id
           ], []}
      end
    end)
  end

  defp get_links(%{local: true, data: data}) do
    h = fn str -> [to_charlist(str)] end

    [
      {:link, [type: ['application/atom+xml'], href: h.(data["object"]["id"]), rel: 'self'], []},
      {:link, [type: ['text/html'], href: h.(data["object"]["id"]), rel: 'alternate'], []}
    ]
  end

  defp get_links(%{
         local: false,
         data: %{
           "object" => %{
             "external_url" => external_url
           }
         }
       }) do
    h = fn str -> [to_charlist(str)] end

    [
      {:link, [type: ['text/html'], href: h.(external_url), rel: 'alternate'], []}
    ]
  end

  defp get_links(_activity), do: []

  defp get_emoji_links(emojis) do
    Enum.map(emojis, fn {emoji, file} ->
      {:link, [name: to_charlist(emoji), rel: 'emoji', href: to_charlist(file)], []}
    end)
  end

  def to_simple_form(activity, user, with_author \\ false)

  def to_simple_form(%{data: %{"object" => %{"type" => "Note"}}} = activity, user, with_author) do
    h = fn str -> [to_charlist(str)] end

    updated_at = activity.data["object"]["published"]
    inserted_at = activity.data["object"]["published"]

    attachments =
      Enum.map(activity.data["object"]["attachment"] || [], fn attachment ->
        url = hd(attachment["url"])

        {:link,
         [rel: 'enclosure', href: to_charlist(url["href"]), type: to_charlist(url["mediaType"])],
         []}
      end)

    in_reply_to = get_in_reply_to(activity.data)
    author = if with_author, do: [{:author, UserRepresenter.to_simple_form(user)}], else: []
    mentions = activity.recipients |> get_mentions

    categories =
      (activity.data["object"]["tag"] || [])
      |> Enum.map(fn tag ->
        if is_binary(tag) do
          {:category, [term: to_charlist(tag)], []}
        else
          nil
        end
      end)
      |> Enum.filter(& &1)

    emoji_links = get_emoji_links(activity.data["object"]["emoji"] || %{})

    summary =
      if activity.data["object"]["summary"] do
        [{:summary, [], h.(activity.data["object"]["summary"])}]
      else
        []
      end

    [
      {:"activity:object-type", ['http://activitystrea.ms/schema/1.0/note']},
      {:"activity:verb", ['http://activitystrea.ms/schema/1.0/post']},
      # For notes, federate the object id.
      {:id, h.(activity.data["object"]["id"])},
      {:title, ['New note by #{user.nickname}']},
      {:content, [type: 'html'],
       h.(activity.data["object"]["content"] |> String.replace(~r/[\n\r]/, ""))},
      {:published, h.(inserted_at)},
      {:updated, h.(updated_at)},
      {:"ostatus:conversation", [ref: h.(activity.data["context"])],
       h.(activity.data["context"])},
      {:link, [ref: h.(activity.data["context"]), rel: 'ostatus:conversation'], []}
    ] ++
      summary ++
      get_links(activity) ++
      categories ++ attachments ++ in_reply_to ++ author ++ mentions ++ emoji_links
  end

  def to_simple_form(%{data: %{"type" => "Like"}} = activity, user, with_author) do
    h = fn str -> [to_charlist(str)] end

    updated_at = activity.data["published"]
    inserted_at = activity.data["published"]

    _in_reply_to = get_in_reply_to(activity.data)
    author = if with_author, do: [{:author, UserRepresenter.to_simple_form(user)}], else: []
    mentions = activity.recipients |> get_mentions

    [
      {:"activity:verb", ['http://activitystrea.ms/schema/1.0/favorite']},
      {:id, h.(activity.data["id"])},
      {:title, ['New favorite by #{user.nickname}']},
      {:content, [type: 'html'], ['#{user.nickname} favorited something']},
      {:published, h.(inserted_at)},
      {:updated, h.(updated_at)},
      {:"activity:object",
       [
         {:"activity:object-type", ['http://activitystrea.ms/schema/1.0/note']},
         # For notes, federate the object id.
         {:id, h.(activity.data["object"])}
       ]},
      {:"ostatus:conversation", [ref: h.(activity.data["context"])],
       h.(activity.data["context"])},
      {:link, [ref: h.(activity.data["context"]), rel: 'ostatus:conversation'], []},
      {:link, [rel: 'self', type: ['application/atom+xml'], href: h.(activity.data["id"])], []},
      {:"thr:in-reply-to", [ref: to_charlist(activity.data["object"])], []}
    ] ++ author ++ mentions
  end

  def to_simple_form(%{data: %{"type" => "Announce"}} = activity, user, with_author) do
    h = fn str -> [to_charlist(str)] end

    updated_at = activity.data["published"]
    inserted_at = activity.data["published"]

    _in_reply_to = get_in_reply_to(activity.data)
    author = if with_author, do: [{:author, UserRepresenter.to_simple_form(user)}], else: []

    retweeted_activity = Activity.get_create_activity_by_object_ap_id(activity.data["object"])
    retweeted_user = User.get_cached_by_ap_id(retweeted_activity.data["actor"])

    retweeted_xml = to_simple_form(retweeted_activity, retweeted_user, true)

    mentions = activity.recipients |> get_mentions

    [
      {:"activity:object-type", ['http://activitystrea.ms/schema/1.0/activity']},
      {:"activity:verb", ['http://activitystrea.ms/schema/1.0/share']},
      {:id, h.(activity.data["id"])},
      {:title, ['#{user.nickname} repeated a notice']},
      {:content, [type: 'html'], ['RT #{retweeted_activity.data["object"]["content"]}']},
      {:published, h.(inserted_at)},
      {:updated, h.(updated_at)},
      {:"ostatus:conversation", [ref: h.(activity.data["context"])],
       h.(activity.data["context"])},
      {:link, [ref: h.(activity.data["context"]), rel: 'ostatus:conversation'], []},
      {:link, [rel: 'self', type: ['application/atom+xml'], href: h.(activity.data["id"])], []},
      {:"activity:object", retweeted_xml}
    ] ++ mentions ++ author
  end

  def to_simple_form(%{data: %{"type" => "Follow"}} = activity, user, with_author) do
    h = fn str -> [to_charlist(str)] end

    updated_at = activity.data["published"]
    inserted_at = activity.data["published"]

    author = if with_author, do: [{:author, UserRepresenter.to_simple_form(user)}], else: []

    mentions = (activity.recipients || []) |> get_mentions

    [
      {:"activity:object-type", ['http://activitystrea.ms/schema/1.0/activity']},
      {:"activity:verb", ['http://activitystrea.ms/schema/1.0/follow']},
      {:id, h.(activity.data["id"])},
      {:title, ['#{user.nickname} started following #{activity.data["object"]}']},
      {:content, [type: 'html'],
       ['#{user.nickname} started following #{activity.data["object"]}']},
      {:published, h.(inserted_at)},
      {:updated, h.(updated_at)},
      {:"activity:object",
       [
         {:"activity:object-type", ['http://activitystrea.ms/schema/1.0/person']},
         {:id, h.(activity.data["object"])},
         {:uri, h.(activity.data["object"])}
       ]},
      {:link, [rel: 'self', type: ['application/atom+xml'], href: h.(activity.data["id"])], []}
    ] ++ mentions ++ author
  end

  # Only undos of follow for now. Will need to get redone once there are more
  def to_simple_form(%{data: %{"type" => "Undo"}} = activity, user, with_author) do
    h = fn str -> [to_charlist(str)] end

    updated_at = activity.data["published"]
    inserted_at = activity.data["published"]

    author = if with_author, do: [{:author, UserRepresenter.to_simple_form(user)}], else: []

    follow_activity =
      if is_map(activity.data["object"]) do
        Activity.get_by_ap_id(activity.data["object"]["id"])
      else
        Activity.get_by_ap_id(activity.data["object"])
      end

    mentions = (activity.recipients || []) |> get_mentions

    if follow_activity do
      [
        {:"activity:object-type", ['http://activitystrea.ms/schema/1.0/activity']},
        {:"activity:verb", ['http://activitystrea.ms/schema/1.0/unfollow']},
        {:id, h.(activity.data["id"])},
        {:title, ['#{user.nickname} stopped following #{follow_activity.data["object"]}']},
        {:content, [type: 'html'],
         ['#{user.nickname} stopped following #{follow_activity.data["object"]}']},
        {:published, h.(inserted_at)},
        {:updated, h.(updated_at)},
        {:"activity:object",
         [
           {:"activity:object-type", ['http://activitystrea.ms/schema/1.0/person']},
           {:id, h.(follow_activity.data["object"])},
           {:uri, h.(follow_activity.data["object"])}
         ]},
        {:link, [rel: 'self', type: ['application/atom+xml'], href: h.(activity.data["id"])], []}
      ] ++ mentions ++ author
    end
  end

  def to_simple_form(%{data: %{"type" => "Delete"}} = activity, user, with_author) do
    h = fn str -> [to_charlist(str)] end

    updated_at = activity.data["published"]
    inserted_at = activity.data["published"]

    author = if with_author, do: [{:author, UserRepresenter.to_simple_form(user)}], else: []

    [
      {:"activity:object-type", ['http://activitystrea.ms/schema/1.0/activity']},
      {:"activity:verb", ['http://activitystrea.ms/schema/1.0/delete']},
      {:id, h.(activity.data["object"])},
      {:title, ['An object was deleted']},
      {:content, [type: 'html'], ['An object was deleted']},
      {:published, h.(inserted_at)},
      {:updated, h.(updated_at)}
    ] ++ author
  end

  def to_simple_form(_, _, _), do: nil

  def wrap_with_entry(simple_form) do
    [
      {
        :entry,
        [
          xmlns: 'http://www.w3.org/2005/Atom',
          "xmlns:thr": 'http://purl.org/syndication/thread/1.0',
          "xmlns:activity": 'http://activitystrea.ms/spec/1.0/',
          "xmlns:poco": 'http://portablecontacts.net/spec/1.0',
          "xmlns:ostatus": 'http://ostatus.org/schema/1.0'
        ],
        simple_form
      }
    ]
  end
end
