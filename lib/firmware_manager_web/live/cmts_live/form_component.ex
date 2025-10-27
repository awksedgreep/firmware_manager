defmodule FirmwareManagerWeb.CmtsLive.FormComponent do
  use FirmwareManagerWeb, :live_component

  alias FirmwareManager.Modem
  alias FirmwareManager.SNMP.PortAllocator

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage CMTS records in your database.</:subtitle>
      </.header>

      <div class="mt-10 space-y-8 bg-gray-800 p-6 rounded-lg shadow">
        <form phx-target={@myself} phx-submit="save" phx-change="change" id="cmts-form">
          <div class="space-y-4">
            <div>
              <label for="name" class="block text-sm font-medium text-gray-300">Name</label>
              <input
                type="text"
                name="name"
                id="name"
                value={@name}
                placeholder="e.g. CMTS Main Office"
                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              />
            </div>

            <div>
              <label for="ip" class="block text-sm font-medium text-gray-300">IP Address</label>
              <input
                type="text"
                name="ip"
                id="ip"
                value={@ip}
                placeholder="e.g. 192.168.1.1"
                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              />
            </div>

            <div>
              <label for="snmp_read" class="block text-sm font-medium text-gray-300">
                SNMP Read Community
              </label>
              <input
                type="text"
                name="snmp_read"
                id="snmp_read"
                value={@snmp_read}
                placeholder="e.g. public"
                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              />
            </div>

            <div>
              <label for="modem_snmp_read" class="block text-sm font-medium text-gray-300">
                Modem SNMP Read Community
              </label>
              <input
                type="text"
                name="modem_snmp_read"
                id="modem_snmp_read"
                value={@modem_snmp_read}
                placeholder="e.g. public"
                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              />
            </div>

            <div>
              <label for="modem_snmp_write" class="block text-sm font-medium text-gray-300">
                Modem SNMP Write Community
              </label>
              <input
                type="text"
                name="modem_snmp_write"
                id="modem_snmp_write"
                value={@modem_snmp_write}
                placeholder="e.g. private"
                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              />
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div>
                <label for="snmp_port" class="block text-sm font-medium text-gray-300">
                  SNMP Port
                </label>
                <input
                  type="number"
                  name="snmp_port"
                  id="snmp_port"
                  value={@snmp_port}
                  placeholder="e.g. 161 (virtual: non-standard like 30161)"
                  class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>
              <div class="flex items-end">
                <label class="inline-flex items-center">
                  <input
                    type="checkbox"
                    name="virtual"
                    id="virtual"
                    value="true"
                    checked={@virtual}
                    class="rounded border-gray-600 bg-gray-700 text-indigo-600 focus:ring-indigo-500"
                  />
                  <span class="ml-2 text-sm text-gray-300">Virtual CMTS</span>
                </label>
              </div>
              <div>
                <label for="modem_count" class="block text-sm font-medium text-gray-300">
                  Simulated Modem Count
                </label>
                <input
                  type="number"
                  min="1"
                  name="modem_count"
                  id="modem_count"
                  value={@modem_count}
                  class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                />
              </div>
            </div>

            <div class="pt-5">
              <button
                type="submit"
                class="inline-flex justify-center rounded-md border border-transparent bg-blue-600 py-2 px-4 text-sm font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
              >
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
    snmp_port: 161,
    modem_snmp_read: "public",
    modem_snmp_write: "private",
    virtual: false,
    modem_count: 4
  }

  @impl true
  def update(%{cmts: cmts} = assigns, socket) do
    # For edit, use the existing values; for new, use the default values
    values =
      if assigns.action == :new do
        # For new CMTS, use default values
        %{
          name: @default_values.name,
          ip: @default_values.ip,
          snmp_read: @default_values.snmp_read,
          snmp_port: @default_values.snmp_port,
          modem_snmp_read: @default_values.modem_snmp_read,
          modem_snmp_write: @default_values.modem_snmp_write,
          virtual: @default_values.virtual,
          modem_count: @default_values.modem_count
        }
      else
        # For existing CMTS, use its values
        %{
          name: cmts.name || "",
          ip: cmts.ip || "",
          snmp_read: cmts.snmp_read || "",
          snmp_port: cmts.snmp_port || 161,
          modem_snmp_read: cmts.modem_snmp_read || "",
          modem_snmp_write: cmts.modem_snmp_write || "",
          virtual: Map.get(cmts, :virtual, false),
          modem_count: Map.get(cmts, :modem_count, 4)
        }
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:name, values.name)
     |> assign(:ip, values.ip)
     |> assign(:snmp_read, values.snmp_read)
     |> assign(:snmp_port, values.snmp_port)
     |> assign(:modem_snmp_read, values.modem_snmp_read)
     |> assign(:modem_snmp_write, values.modem_snmp_write)
     |> assign(:virtual, values.virtual)
     |> assign(:modem_count, values.modem_count)}
  end

  @impl true
  def handle_event("save", params, socket) do
    save_cmts(socket, socket.assigns.action, params)
  end

  @impl true
  def handle_event("change", params, socket) do
    # Reflect raw form values back into assigns
    ip = params["ip"] || socket.assigns.ip
    snmp_read = params["snmp_read"] || socket.assigns.snmp_read
    modem_snmp_read = params["modem_snmp_read"] || socket.assigns.modem_snmp_read
    modem_snmp_write = params["modem_snmp_write"] || socket.assigns.modem_snmp_write
    snmp_port = parse_int(params["snmp_port"], socket.assigns.snmp_port || 161)
    virtual? = truthy?(params["virtual"])
    modem_count = parse_int(params["modem_count"], socket.assigns.modem_count || 4)

    {ip, snmp_port} =
      if virtual? do
        # When toggled on, set localhost and allocate a unique non-standard port if current is default
        new_ip = "127.0.0.1"
        new_port = if snmp_port == 161, do: PortAllocator.next_port(), else: snmp_port
        {new_ip, new_port}
      else
        # When toggled off, reset port to standard if it was previously virtual-looking
        new_port = if snmp_port != 161, do: 161, else: snmp_port
        {ip, new_port}
      end

    {:noreply,
     socket
     |> assign(:ip, ip)
     |> assign(:snmp_read, snmp_read)
     |> assign(:modem_snmp_read, modem_snmp_read)
     |> assign(:modem_snmp_write, modem_snmp_write)
     |> assign(:snmp_port, snmp_port)
     |> assign(:virtual, virtual?)
     |> assign(:modem_count, modem_count)}
  end

  defp save_cmts(socket, :edit, params) do
    case Modem.update_cmts(socket.assigns.cmts, %{
           name: params["name"],
           ip: params["ip"],
           snmp_read: params["snmp_read"],
           snmp_port: resolved_port(params["snmp_port"], truthy?(params["virtual"])),
           modem_snmp_read: params["modem_snmp_read"],
           modem_snmp_write: params["modem_snmp_write"],
           virtual: truthy?(params["virtual"]),
           modem_count: parse_int(params["modem_count"], 4)
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
         |> assign(:snmp_port, parse_int(params["snmp_port"], 161))
         |> assign(:modem_snmp_read, params["modem_snmp_read"] || "")
         |> assign(:modem_snmp_write, params["modem_snmp_write"] || "")
         |> assign(:virtual, truthy?(params["virtual"]))
         |> assign(:modem_count, parse_int(params["modem_count"], 4))}
    end
  end

  defp save_cmts(socket, :new, params) do
    case Modem.create_cmts(%{
           name: params["name"],
           ip: params["ip"],
           snmp_read: params["snmp_read"],
           snmp_port: resolved_port(params["snmp_port"], truthy?(params["virtual"])),
           modem_snmp_read: params["modem_snmp_read"],
           modem_snmp_write: params["modem_snmp_write"],
           virtual: truthy?(params["virtual"]),
           modem_count: parse_int(params["modem_count"], @default_values.modem_count)
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
         |> assign(:snmp_port, parse_int(params["snmp_port"], @default_values.snmp_port))
         |> assign(:modem_snmp_read, params["modem_snmp_read"] || "")
         |> assign(:modem_snmp_write, params["modem_snmp_write"] || "")
         |> assign(:virtual, truthy?(params["virtual"]))
         |> assign(:modem_count, parse_int(params["modem_count"], @default_values.modem_count))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp resolved_port(nil, is_virtual) when is_virtual, do: PortAllocator.next_port()
  defp resolved_port("", is_virtual) when is_virtual, do: PortAllocator.next_port()

  defp resolved_port(val, is_virtual) do
    port = parse_int(val, 161)

    cond do
      is_virtual and port == 161 -> PortAllocator.next_port()
      not is_virtual -> 161
      true -> port
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default
  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> default
    end
  end

  defp truthy?(val) when is_binary(val), do: val in ["true", "on", "1", "yes"]
  defp truthy?(val) when is_boolean(val), do: val
  defp truthy?(_), do: false
end
