defmodule Bonfire.Boundaries.Grants do

  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Boundaries.Accesses

  import Bonfire.Boundaries.Integration
  import Ecto.Query

  def grants do
    %{ read_only:  "GRANT0N1YACCESS1SREADACCES"}
  end

  def grant(subject_id, acl_id, access \\ :read_only)

  def grant(subject_ids, acl_id, access) when is_list(subject_ids), do: subject_ids |> subject_id() |> Enum.uniq() |> Enum.map(&grant(&1, acl_id, access)) #|> IO.inspect(label: "mapped") # TODO: optimise?

  def grant(subject_id, acl_id, access) when is_atom(access), do: grant(subject_id, acl_id, Accesses.accesses[access])

  def grant(subject_id, acl_id, access_id) when is_binary(subject_id) and is_binary(acl_id) and is_binary(access_id) do
    # IO.inspect(grant: subject_id)
    create(%{
      subject_id: subject_id, # who we are granting access to
      acl_id:     acl_id, # what (list of) things we are granting access to
      access_id:  access_id, # what level of access
    }) #|> IO.inspect
  end

  def grant(subject_id, acl_id, access) when not is_nil(subject_id) do
    # IO.inspect(subject_id: subject_id)
    subject_id(subject_id) |> grant(acl_id, access)
  end

  def grant(_, _, _), do: nil


  def subject_id(subjects) when is_list(subjects), do: Enum.map(subjects, &subject_id/1)
  def subject_id(circle_name) when is_atom(circle_name) and not is_nil(circle_name), do: Bonfire.Boundaries.Circles.get_id(circle_name)
  def subject_id(%{id: subject_id}), do: subject_id
  def subject_id(subject_id) when is_binary(subject_id), do: subject_id
  def subject_id(_), do: nil


  def create(%{}=attrs) when not is_struct(attrs) do
    repo().insert(changeset(attrs))
  end

  def changeset(access \\ %Grant{}, attrs) do
    Grant.changeset(access, attrs)
  end

  def list, do: repo().many(from(
    u in Grant,
    left_join: acl in assoc(u, :acl),
    left_join: named in assoc(acl, :named),
    left_join: access in assoc(u, :access),
    preload: [:subject_profile, :subject_named, acl: [:named], access: [interacts: [:verb]]]
  ))

end
