defmodule FirmwareManagerWeb.CmtsLive.Show do
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
     |> assign(:page_title, "CMTS Details")
     |> assign(:cmts, Modem.get_cmts!(id))}
  end
end
