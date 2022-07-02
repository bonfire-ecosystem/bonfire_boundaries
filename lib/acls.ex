defmodule Bonfire.Boundaries.Acls do
  @moduledoc """
  acls represent fully populated access control rules that can be reused
  """
  use Arrows
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  import Ecto.Query
  import EctoSparkles
  import Bonfire.Boundaries.Integration
  import Bonfire.Boundaries.Queries

  alias Bonfire.Data.AccessControl.Acl
  # alias Bonfire.Data.Identity.Named
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.Stereotyped
  alias Bonfire.Data.AccessControl.{Acl, Controlled, Grant}
  # alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.Acls
  # alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Verbs
  alias Ecto.Changeset
  alias Pointers.{Changesets, ULID}

  @exclude_stereotypes ["2HEYS11ENCEDMES0CAN0TSEEME"] # don't show "others who silenced me"

  # special built-in acls (eg, guest, local, activity_pub)
  def acls, do: Bonfire.Common.Config.get([:acls])

  def get(slug) when is_atom(slug), do: acls()[slug]
  def get!(slug) when is_atom(slug) do
    get(slug)
      # || ( Bonfire.Boundaries.Fixtures.insert && get(slug) )
      || raise RuntimeError, message: "Missing default acl: #{inspect(slug)}"
  end

  def get_id(slug), do: e(acls(), slug, :id, nil)
  def get_id!(slug), do: get!(slug)[:id]


  def cast(changeset, creator, opts) do
    # id = Changeset.get_field(changeset, :id)
    base = base_acls(creator, opts)
    case custom_grants(changeset, opts) do
      [] ->
        changeset
        |> Changesets.put_assoc(:controlled, base)
      grants ->
        acl_id = ULID.generate()
        controlled = [%{acl_id: acl_id} | base]
        grants =
          (e(opts, :verbs_to_grant, nil) || Config.get!([:verbs_to_grant, :default])) |> debug("verbs_to_grant")
          |> Enum.flat_map(grants, &grant_to(ulid(&1), acl_id, ...))

        changeset
        |> Changeset.prepare_changes(fn changeset ->
          changeset.repo.insert!(%Acl{id: acl_id})
          changeset.repo.insert_all(Grant, grants)
          changeset
        end)
        |> Changesets.put_assoc(:controlled, controlled)
    end
  end

  # when the user picks a preset, this maps to a set of base acls
  defp base_acls(user, opts) do
    preset = Boundaries.preset(opts)

    (
      Config.get!([:object_default_boundaries, :acls])
      ++
      Boundaries.acls_from_preset_boundary_name(preset)
    )
    |> debug("preset ACLs to set")
    |> find_acls(user)
    |> maybe_add_custom(preset)
    |> debug("ACLs to set")
  end

  defp maybe_add_custom(acls, preset) do
    if is_ulid?(preset) do
      acls ++ [%{acl_id: preset}]
    else
      acls
    end
  end

  defp custom_grants(changeset, opts) do
    (
      reply_to_grants(changeset, opts)
      ++ mentions_grants(changeset, opts)
      ++ maybe_custom_circles_or_users(opts)
    )
    |> Enum.uniq()
    |> filter_empty([])
  end

  defp maybe_custom_circles_or_users(opts), do: maybe_from_opts(opts, :to_circles, [])

  defp reply_to_grants(changeset, opts) do
    reply_to_creator = Utils.e(changeset, :changes, :replied, :changes, :replying_to, :created, :creator, nil)

    if reply_to_creator do
      # debug(reply_to_creator, "creators of reply_to should be added to a new ACL")

      case Boundaries.preset(opts) do
        "public" ->
          [ulid(reply_to_creator)]
        "local" ->
          if is_local?(reply_to_creator), do: [ulid(reply_to_creator)],
          else: []
        _ -> []
      end
    else
      []
    end
  end

  defp mentions_grants(changeset, opts) do
    mentions = Utils.e(changeset, :changes, :post_content, :changes, :mentions, nil)

    if mentions && mentions !=[] do
      # debug(mentions, "mentions/tags may be added to a new ACL")

      case Boundaries.preset(opts) do
        "public" ->
          ulid(mentions)
        "mentions" ->
          ulid(mentions)
        "local" ->
          ( # include only if local
            mentions
            |> Enum.filter(&is_local?/1)
            |> ulid()
          )
        _ ->
        # do not grant to mentions by default
        []
      end
    else
      []
    end
  end

  defp find_acls(acls, user) when is_list(acls) and length(acls)>0 and ( is_binary(user) or is_map(user) ) do
    acls =
      acls
      |> Enum.map(&identify/1)
      # |> info("identified")
      |> filter_empty([])
      |> Enum.group_by(&elem(&1, 0))
    globals =
      acls
      |> Map.get(:global, [])
      |> Enum.map(&elem(&1, 1))
      # |> info("globals")
    stereo =
      case Map.get(acls, :stereo, []) do
        [] -> []
        stereo ->
          stereo
          |> Enum.map(&elem(&1, 1).id)
          |> Acls.find_caretaker_stereotypes(user, ...)
          # |> info("stereos")
      end
    Enum.map(globals ++ stereo, &(%{acl_id: &1.id}))
  end
  defp find_acls(_acls, _) do
    warn("You need to provide an object creator to properly set ACLs")
    []
  end

  defp identify(name) do
    case user_default_acl(name) do

      nil -> # seems to be a global ACL
        {:global, Acls.get!(name)}

      default -> # should be a user-level stereotyped ACL
        case default[:stereotype] do
          nil -> raise RuntimeError, message: "Boundaries: Unstereotyped user acl in config: #{inspect(name)}"
          stereo -> {:stereo, Acls.get!(stereo)}
        end
    end
  end

  defp grant_to(user_etc, acl_id, verbs) when is_list(verbs), do: Enum.map(verbs, &grant_to(user_etc, acl_id, &1))

  defp grant_to(user_etc, acl_id, verb) do
    %{
      id: ULID.generate(),
      acl_id: acl_id,
      subject_id: user_etc,
      verb_id: Verbs.get_id!(verb),
      value: true
    }
  end


  ## invariants:

  ## * All a user's ACLs will have the user as an administrator but it
  ##   will be hidden from the user

  def create(attrs \\ %{}, opts) do
    changeset(:create, attrs, opts)
    |> repo().insert()
  end

  def changeset(:create, attrs, opts) do
    changeset(:create, attrs, opts, Keyword.fetch!(opts, :current_user))
  end

  defp changeset(:create, attrs, _opts, :system), do: Acls.changeset_cast(attrs)
  defp changeset(:create, attrs, _opts, %{id: id}) do
    Changeset.cast(%Acl{}, %{caretaker: %{caretaker_id: id}}, [])
    |> changeset_cast(attrs)
  end

  def changeset_cast(acl \\ %Acl{}, attrs) do
    Acl.changeset(acl, attrs)
    # |> IO.inspect(label: "cs")
    |> Changeset.cast_assoc(:named, [])
    |> Changeset.cast_assoc(:caretaker)
    |> Changeset.cast_assoc(:stereotyped)
  end

  def get_for_caretaker(id, caretaker, opts \\ []) do
    repo().single(get_q(id, caretaker, opts))
  end

  def get_q(id, caretaker, opts \\ []) do
    list_q(opts ++ [skip_boundary_check: true])
    # |> reusable_join(:inner, [circle: circle], caretaker in assoc(circle, :caretaker), as: :caretaker)
    |> maybe_for_caretaker(id, caretaker)
  end

  defp maybe_for_caretaker(query, id, caretaker) do
    if id in built_in_ids do
      query
      |> where([acl], acl.id == ^ulid!(id))
    else
      query
      # |> reusable_join(:inner, [circle: circle], caretaker in assoc(circle, :caretaker), as: :caretaker)
      |> where([acl, caretaker: caretaker], acl.id == ^ulid!(id) and caretaker.caretaker_id == ^ulid!(caretaker))
    end
  end

  @doc """
  Lists ACLs we are permitted to see.
  """
  def list(opts \\ []) do
    list_q(opts)
    |> repo().many()
  end

  def list_q(opts \\ []) do
    from(acl in Acl, as: :acl)
    |> boundarise(acl.id, opts)
    |> proload([:caretaker, :named, stereotyped: {"stereotype_", [:named]}])
  end

  # def list_all do
  #   from(u in Acl, as: :acl)
  #   |> proload([:named, :controlled, :stereotyped, :caretaker])
  #   |> repo().many()
  # end

  def built_in_ids do
    Config.get(:acls)
    |> Map.values()
    |> Enum.map(& &1.id)
  end

  def list_built_ins do
    list_q(skip_boundary_check: true)
    |> where([acl], acl.id in ^built_in_ids)
    |> repo().many()
  end

  def built_in_for_dropdown do # TODO
    filter = Config.get(:acls_to_present)
    Config.get(:acls)
    |> Enum.filter(fn {name, acl} -> name in filter end)
    |> Enum.map(fn {name, acl} -> acl.id end)
  end

  def for_dropdown(opts) do
    built_ins = built_in_for_dropdown()
    list_my_with_counts(current_user(opts), opts ++ [extra_ids_to_include: built_ins, exclude_ids: @exclude_stereotypes ++ ["71MAYADM1N1STERMY0WNSTVFFS", "0H0STEDCANTSEE0RD0ANYTH1NG", "1S11ENCEDTHEMS0CAN0TP1NGME"]])
  end

  @doc """
  Lists the ACLs we are the registered caretakers of that we are
  permitted to see. If any are created without permitting the
  user to see them, they will not be shown.
  """
  def list_my(user, opts \\ []), do: repo().many(list_my_q(user, opts))

  def list_my_with_counts(user, opts \\ []) do
    list_my_q(user, opts)
    |> join(:left, [acl], grants in subquery(from g in Grant,
      group_by: g.acl_id,
      select: %{acl_id: g.acl_id, count: count()}
    ), on: grants.acl_id == acl.id, as: :grants)
    |> join(:left, [acl], controlled in subquery(from c in Controlled,
      group_by: c.acl_id,
      select: %{acl_id: c.acl_id, count: count()}
    ), on: controlled.acl_id == acl.id, as: :controlled)
    |> select_merge([grants: grants, controlled: controlled], %{grants_count: grants.count, controlled_count: controlled.count})
    |> order_by([grants: grants, controlled: controlled], desc_nulls_last: controlled.count, desc_nulls_last: grants.count)
    |> repo().many()
  end

  @doc "query for `list_my`"
  def list_my_q(user, opts \\ []) do
    list_q(skip_boundary_check: true)
    |> where([acl, caretaker: caretaker], caretaker.caretaker_id == ^ulid!(user) or (acl.id in ^e(opts, :extra_ids_to_include, []) and acl.id not in ^e(opts, :exclude_ids, @exclude_stereotypes)))
    |> where([stereotyped: stereotyped], is_nil(stereotyped.id) or stereotyped.stereotype_id not in ^e(opts, :exclude_ids, @exclude_stereotypes))
  end

  def user_default_acl(name), do: user_default_acls()[name]

  def user_default_acls() do # FIXME: this vs acls/0 ?
    Boundaries.user_default_boundaries()
    |> Map.fetch!(:acls)
    # |> dump
  end

  def find_caretaker_stereotypes(caretaker, stereotypes) do
    from(a in Acl,
      join: c in Caretaker,  on: a.id == c.id and c.caretaker_id == ^ulid(caretaker),
      join: s in Stereotyped, on: a.id == s.id and s.stereotype_id in ^stereotypes,
      preload: [caretaker: c, stereotyped: s]
    ) |> repo().all()
    # |> debug("stereotype acls")
  end

end
