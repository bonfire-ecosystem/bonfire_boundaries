defmodule Bonfire.Boundaries.Web.BlocksLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Integration

  prop selected_tab, :string
  prop blocks, :list, default: []
  prop page_info, :any
  prop scope, :atom, default: nil

  def update(assigns, socket) do
    current_user = current_user(assigns)
    tab = e(assigns, :selected_tab, nil)

    scope =
      if Integration.is_admin?(current_user) ||
           Bonfire.Boundaries.can?(current_user, :block, :instance),
         do: e(assigns, :scope, nil)

    block_type = if tab == "ghosted", do: :ghost, else: :silence

    circle = Bonfire.Boundaries.Blocks.list(block_type, scope || current_user)

    # |> debug

    blocks = e(circle, :encircles, [])

    # |> debug

    # blocks = for block <- blocks, do: %{activity:
    #   block
    #   |> Map.put(:verb, %{verb: block_type})
    #   |> Map.put(:object, e(block, :subject, nil))
    #   |> Map.put(:subject, e(block, :caretaker, nil))
    # } #|> debug

    {:ok,
     assign(
       socket,
       # user or instance-wide?
       scope: scope,
       page: tab,
       selected_tab: tab,
       block_type: block_type,
       # page_title: l("Blocks")<>" - #{scope} #{tab}",
       current_user: current_user,
       blocks: blocks

       # page_info: e(q, :page_info, [])
     )}
  end
end
