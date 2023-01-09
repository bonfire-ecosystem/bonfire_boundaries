defmodule Bonfire.Boundaries.Web.SidebarNavLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :string
  prop id, :string, default: nil

  prop class, :css_class, default: "gap-1 my-2 menu !flex"

  declare_nav_component("Links to boundaries & circles management pages")
  declare_settings_nav_component("Links to boundaries & circles management pages")
end
