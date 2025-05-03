defmodule FirmwareManagerWeb.CmtsLive.Index do
  use FirmwareManagerWeb, :live_view

  alias FirmwareManager.Modem
  alias FirmwareManager.Modem.Cmts

  @impl true
  def mount(_params, _session, socket) do
    # Fetch CMTS records and assign them directly to the socket
    {:ok, assign(socket, :cmts_collection, Modem.list_cmts())}
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
  def handle_info({FirmwareManagerWeb.CmtsLive.FormComponent, {:saved, _cmts}}, socket) do
    # Reload the entire CMTS collection after a save
    {:noreply, assign(socket, :cmts_collection, Modem.list_cmts())}
  end

  @impl true
  def handle_event("delete_cmts", %{"id" => id}, socket) do
    # Get the CMTS record
    cmts = Modem.get_cmts!(id)
    
    # Try to delete it
    case Modem.delete_cmts(cmts) do
      {:ok, _deleted_cmts} ->
        # Reload the CMTS collection after successful deletion
        {:noreply, 
         socket
         |> assign(:cmts_collection, Modem.list_cmts())
         |> put_flash(:info, "CMTS deleted successfully.")}
        
      {:error, changeset} ->
        # Handle error case
        {:noreply, 
         socket
         |> put_flash(:error, "Could not delete CMTS: #{inspect(changeset.errors)}")}
    end
  end
end
