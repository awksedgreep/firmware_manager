defmodule FirmwareManagerWeb.CmtsLive.Index do
  use FirmwareManagerWeb, :live_view

  alias FirmwareManager.Modem
  alias FirmwareManager.Modem.Cmts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :cmts_collection, Modem.list_cmts())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit CMTS")
    |> assign(:cmts, Modem.get_cmts!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New CMTS")
    |> assign(:cmts, %Cmts{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing CMTS")
    |> assign(:cmts, nil)
  end

  @impl true
  def handle_info({FirmwareManagerWeb.CmtsLive.FormComponent, {:saved, cmts}}, socket) do
    {:noreply, stream_insert(socket, :cmts_collection, cmts)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    cmts = Modem.get_cmts!(id)
    {:ok, _} = Modem.delete_cmts(cmts)

    {:noreply, stream_delete(socket, :cmts_collection, cmts)}
  end
end
