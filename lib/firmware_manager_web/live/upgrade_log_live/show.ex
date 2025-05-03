defmodule FirmwareManagerWeb.UpgradeLogLive.Show do
  use FirmwareManagerWeb, :live_view

  alias FirmwareManager.Modem

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:upgrade_log, Modem.get_upgrade_log!(id))}
  end

  defp page_title(:show), do: "Show Upgrade log"
  defp page_title(:edit), do: "Edit Upgrade log"
end
