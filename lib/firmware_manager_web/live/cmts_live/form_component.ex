defmodule FirmwareManagerWeb.CmtsLive.FormComponent do
  use FirmwareManagerWeb, :live_component

  alias FirmwareManager.Modem

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage CMTS records in your database.</:subtitle>
      </.header>

      <div class="mt-10 space-y-8 bg-gray-800 p-6 rounded-lg shadow">
        <form phx-target={@myself} phx-submit="save" id="cmts-form">
          <div class="space-y-4">
            <div>
              <label for="name" class="block text-sm font-medium text-gray-300">Name</label>
              <input type="text" name="name" id="name" value={@name} placeholder="e.g. CMTS Main Office" 
                     class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" />
            </div>
            
            <div>
              <label for="ip" class="block text-sm font-medium text-gray-300">IP Address</label>
              <input type="text" name="ip" id="ip" value={@ip} placeholder="e.g. 192.168.1.1" 
                     class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" />
            </div>
            
            <div>
              <label for="snmp_read" class="block text-sm font-medium text-gray-300">SNMP Read Community</label>
              <input type="text" name="snmp_read" id="snmp_read" value={@snmp_read} placeholder="e.g. public" 
                     class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" />
            </div>
            
            <div>
              <label for="modem_snmp_read" class="block text-sm font-medium text-gray-300">Modem SNMP Read Community</label>
              <input type="text" name="modem_snmp_read" id="modem_snmp_read" value={@modem_snmp_read} placeholder="e.g. public" 
                     class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" />
            </div>
            
            <div>
              <label for="modem_snmp_write" class="block text-sm font-medium text-gray-300">Modem SNMP Write Community</label>
              <input type="text" name="modem_snmp_write" id="modem_snmp_write" value={@modem_snmp_write} placeholder="e.g. private" 
                     class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" />
            </div>
            
            <div class="pt-5">
              <button type="submit" class="inline-flex justify-center rounded-md border border-transparent bg-blue-600 py-2 px-4 text-sm font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2">
                Save CMTS
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
    """
  end

  # Default values for new CMTS records
  @default_values %{
    name: "",
    ip: "10.10.10.10",
    snmp_read: "public",
    modem_snmp_read: "public",
    modem_snmp_write: "private"
  }

  @impl true
  def update(%{cmts: cmts} = assigns, socket) do
    # For edit, use the existing values; for new, use the default values
    values = if assigns.action == :new do
      # For new CMTS, use default values
      %{
        name: @default_values.name,
        ip: @default_values.ip,
        snmp_read: @default_values.snmp_read,
        modem_snmp_read: @default_values.modem_snmp_read,
        modem_snmp_write: @default_values.modem_snmp_write
      }
    else
      # For existing CMTS, use its values
      %{
        name: cmts.name || "",
        ip: cmts.ip || "",
        snmp_read: cmts.snmp_read || "",
        modem_snmp_read: cmts.modem_snmp_read || "",
        modem_snmp_write: cmts.modem_snmp_write || ""
      }
    end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:name, values.name)
     |> assign(:ip, values.ip)
     |> assign(:snmp_read, values.snmp_read)
     |> assign(:modem_snmp_read, values.modem_snmp_read)
     |> assign(:modem_snmp_write, values.modem_snmp_write)}
  end

  @impl true
  def handle_event("save", params, socket) do
    save_cmts(socket, socket.assigns.action, params)
  end

  defp save_cmts(socket, :edit, params) do
    case Modem.update_cmts(socket.assigns.cmts, %{
      name: params["name"],
      ip: params["ip"],
      snmp_read: params["snmp_read"],
      modem_snmp_read: params["modem_snmp_read"],
      modem_snmp_write: params["modem_snmp_write"]
    }) do
      {:ok, cmts} ->
        notify_parent({:saved, cmts})

        {:noreply,
         socket
         |> put_flash(:info, "CMTS updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, error} ->
        IO.inspect(error, label: "Update CMTS Error")
        {:noreply,
         socket
         |> put_flash(:error, "Failed to update CMTS")
         |> assign(:name, params["name"] || "")
         |> assign(:ip, params["ip"] || "")
         |> assign(:snmp_read, params["snmp_read"] || "")
         |> assign(:modem_snmp_read, params["modem_snmp_read"] || "")
         |> assign(:modem_snmp_write, params["modem_snmp_write"] || "")}
    end
  end

  defp save_cmts(socket, :new, params) do
    case Modem.create_cmts(%{
      name: params["name"],
      ip: params["ip"],
      snmp_read: params["snmp_read"],
      modem_snmp_read: params["modem_snmp_read"],
      modem_snmp_write: params["modem_snmp_write"]
    }) do
      {:ok, cmts} ->
        notify_parent({:saved, cmts})

        {:noreply,
         socket
         |> put_flash(:info, "CMTS created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, error} ->
        IO.inspect(error, label: "Create CMTS Error")
        {:noreply,
         socket
         |> put_flash(:error, "Failed to create CMTS")
         |> assign(:name, params["name"] || "")
         |> assign(:ip, params["ip"] || "")
         |> assign(:snmp_read, params["snmp_read"] || "")
         |> assign(:modem_snmp_read, params["modem_snmp_read"] || "")
         |> assign(:modem_snmp_write, params["modem_snmp_write"] || "")}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
