defmodule Bonfire.Boundaries.Web.NewAclLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop event_target, :any
  prop setting_boundaries, :boolean, default: false

end
