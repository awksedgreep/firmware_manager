defmodule FirmwareManagerWeb.FirmwareManagerWeb.UpgradeLogLive.Index do
  use FirmwareManagerWeb, :live_view

  @default_page_size 20
  @default_sort_by :upgraded_at
  @default_sort_dir :desc

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> stream(:upgrade_logs, [])
      |> assign(:page, 1)
      |> assign(:page_size, @default_page_size)
      |> assign(:sort_by, @default_sort_by)
      |> assign(:sort_dir, @default_sort_dir)
      |> assign(:sort_options, [
        %{field: :mac_address, label: "Mac address"},
        %{field: :old_sysdescr, label: "Old sysdescr"},
        %{field: :new_sysdescr, label: "New sysdescr"},
        %{field: :new_firmware, label: "New firmware"},
        %{field: :upgraded_at, label: "Upgraded at"}
      ])
      |> load_upgrade_logs()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")
    page_size = String.to_integer(params["page_size"] || to_string(@default_page_size))
    sort_by = (params["sort_by"] || to_string(@default_sort_by)) |> String.to_atom()
    sort_dir = (params["sort_dir"] || to_string(@default_sort_dir)) |> String.to_atom()

    socket =
      socket
      |> assign(:page, page)
      |> assign(:page_size, page_size)
      |> assign(:sort_by, sort_by)
      |> assign(:sort_dir, sort_dir)
      |> load_upgrade_logs()

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp load_upgrade_logs(socket) do
    %{page: page, page_size: page_size, sort_by: sort_by, sort_dir: sort_dir} = socket.assigns

    # Calculate offset for pagination
    offset = (page - 1) * page_size

    # Get total count for pagination using a count query without limit
    total_query = FirmwareManager.Modem.list_upgrade_logs(limit: :infinity)
    total_entries = Enum.count(total_query)
    total_pages = ceil(total_entries / page_size)

    # Get paginated data
    upgrade_logs = FirmwareManager.Modem.list_upgrade_logs(
      limit: page_size,
      offset: offset,
      sort_by: sort_by,
      sort: sort_dir
    )
    
    # Convert Ash resources to maps with IDs for the stream
    upgrade_logs_with_ids = Enum.map(upgrade_logs, fn log -> %{id: log.id, mac_address: log.mac_address, old_sysdescr: log.old_sysdescr, new_sysdescr: log.new_sysdescr, new_firmware: log.new_firmware, upgraded_at: log.upgraded_at} end)

    socket
    |> assign(:total_entries, total_entries)
    |> assign(:total_pages, total_pages)
    |> stream(:upgrade_logs, upgrade_logs_with_ids, reset: true)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Upgrade logs")
    |> assign(:upgrade_log, nil)
  end

  @impl true
  def handle_info({FirmwareManagerWeb.FirmwareManagerWeb.UpgradeLogLive.FormComponent, {:saved, upgrade_log}}, socket) do
    {:noreply, stream_insert(socket, :upgrade_logs, upgrade_log)}
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)
    current_sort_by = socket.assigns.sort_by
    current_sort_dir = socket.assigns.sort_dir
    
    # If clicking the same column, toggle the sort direction
    {sort_by, sort_dir} = if field == current_sort_by do
      {field, if(current_sort_dir == :asc, do: :desc, else: :asc)}
    else
      # Default to ascending for a new column
      {field, :asc}
    end
    
    socket = 
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:sort_dir, sort_dir)
      |> assign(:page, 1) # Reset to first page when sorting changes
      |> load_upgrade_logs()
      
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("pagination", %{"page" => "$PAGE$"}, socket) do
    # This is a special case for the placeholder value
    # The actual page number will be replaced by the component
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("pagination", %{"action" => action, "page" => page, "value" => _}, socket) when action == "select" do
    # Handle the select action from pagination component
    {page_num, _} = Integer.parse(to_string(page))
    
    socket =
      socket
      |> assign(:page, page_num)
      |> load_upgrade_logs()
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("pagination", %{"page" => page}, socket) when is_integer(page) do
    socket =
      socket
      |> assign(:page, page)
      |> load_upgrade_logs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("pagination", %{"page" => page}, socket) do
    case Integer.parse(to_string(page)) do
      {page_num, _} ->
        socket =
          socket
          |> assign(:page, page_num)
          |> load_upgrade_logs()

        {:noreply, socket}
      :error ->
        # Handle the case where page is not a valid integer
        {:noreply, socket}
    end
  end
end
