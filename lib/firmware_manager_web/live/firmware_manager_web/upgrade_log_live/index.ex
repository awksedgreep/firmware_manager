defmodule FirmwareManagerWeb.FirmwareManagerWeb.UpgradeLogLive.Index do
  use FirmwareManagerWeb, :live_view

  alias FirmwareManager.Modem
  alias FirmwareManager.Modem.UpgradeLog

  @default_page_size 20
  @default_sort_by :upgraded_at
  @default_sort_dir :desc

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page, 1)
      |> assign(:page_size, @default_page_size)
      |> assign(:sort_by, @default_sort_by)
      |> assign(:sort_dir, @default_sort_dir)
      |> assign(:total_entries, 0)
      |> assign(:total_pages, 0)
      |> stream(:upgrade_logs, [])

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

    # Get total count for pagination
    total_query = FirmwareManager.Modem.list_upgrade_logs()
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
    upgrade_logs_with_ids = Enum.map(upgrade_logs, fn log -> {log.id, log} end)

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
  def handle_event("paginate", %{"page" => "$PAGE$"}, socket) do
    # This is a placeholder for the pagination component
    # The actual page will be passed in the other pattern match
    {:noreply, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) when is_integer(page) do
    socket =
      socket
      |> assign(:page, page)
      |> load_upgrade_logs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    {page, _} = Integer.parse(page)

    socket =
      socket
      |> assign(:page, page)
      |> load_upgrade_logs()

    {:noreply, socket}
  end
end
