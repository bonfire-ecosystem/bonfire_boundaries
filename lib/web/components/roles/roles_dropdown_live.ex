defmodule Bonfire.Boundaries.Web.RolesDropdownLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop circle_id, :string, default: nil
  prop role, :any, default: nil
  prop scope, :any, default: nil
  prop usage, :any, default: nil
  prop extra_roles, :list, default: []
  prop setting_boundaries, :boolean, default: false
end
