defmodule FirmwareManagerWeb.UpgradesLive do
  use FirmwareManagerWeb, :live_view
  alias FirmwareManager.Modem
  alias FirmwareManager.Rules.RuleMatcher
  alias FirmwareManager.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:mac_rule, "")
     |> assign(:sys_glob, "")
     |> assign(:firmware_file, "")
     |> assign(:tftp_server, Settings.tftp_server())
     |> assign(:force, false)
     |> assign(:preview, [])
     |> assign(:error, nil)
     |> assign(:results, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mac_rule = Map.get(params, "mac_rule")
    sys_glob = Map.get(params, "sysdescr_glob") || Map.get(params, "sys_glob")
    fw_file = Map.get(params, "firmware_file")
    tftp = Map.get(params, "tftp_server")
    force = Map.get(params, "force") in ["true", "on", "1"]
    do_action = Map.get(params, "do")
    rule_id = Map.get(params, "rule_id")

    socket =
      socket
      |> assign(:mac_rule, mac_rule || socket.assigns.mac_rule)
      |> assign(:sys_glob, sys_glob || socket.assigns.sys_glob)
      |> assign(:firmware_file, fw_file || socket.assigns.firmware_file)
      |> assign(:tftp_server, tftp || socket.assigns.tftp_server)
      |> assign(:force, force || socket.assigns.force)

    cond do
      (fw_file && fw_file != "") and do_action in ["run", "preview"] ->
        selected = Modem.list_cmts()
        opts = %{firmware_file: fw_file}
        opts = if mac_rule && mac_rule != "", do: Map.put(opts, :mac_rule, mac_rule), else: opts

        opts =
          if sys_glob && sys_glob != "", do: Map.put(opts, :sysdescr_glob, sys_glob), else: opts

        opts = if tftp && tftp != "", do: Map.put(opts, :tftp_server, tftp), else: opts
        opts = Map.put(opts, :force?, force)

        case RuleMatcher.plan_upgrades_multi(selected, opts) do
          {:ok, plan0} ->
            plan = if rule_id, do: Enum.map(plan0, &Map.put(&1, :rule_id, rule_id)), else: plan0

            case do_action do
              "run" ->
                {:ok, results} =
                  RuleMatcher.apply_plan_multi(plan,
                    concurrency: 6,
                    poll_ms: 300,
                    poll_attempts: 50
                  )

                {:noreply,
                 socket
                 |> assign(:preview, plan)
                 |> assign(:results, results)
                 |> put_flash(:info, "Upgrade plan executing; results updated.")}

              _ ->
                {:noreply,
                 socket
                 |> assign(:preview, plan)
                 |> assign(:results, [])}
            end

          {:error, reason} ->
            {:noreply, assign(socket, error: inspect(reason), preview: [], results: [])}
        end

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_cmts", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_all", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("preview", params, socket) do
    mac_rule = Map.get(params, "mac_rule", "")
    sys_glob = Map.get(params, "sysdescr_glob", "")
    fw_file = Map.get(params, "firmware_file", "")
    tftp = Map.get(params, "tftp_server", "")
    do_action = Map.get(params, "do", "preview")
    force = Map.get(params, "force") in ["true", "on", "1"]

    if fw_file == "" do
      {:noreply, assign(socket, error: "Firmware file is required", preview: [], results: [])}
    else
      # Use all known CMTS behind the scenes; rules are CMTS-agnostic
      selected = Modem.list_cmts()

      opts = %{firmware_file: fw_file}
      opts = if mac_rule != "", do: Map.put(opts, :mac_rule, mac_rule), else: opts
      opts = if sys_glob != "", do: Map.put(opts, :sysdescr_glob, sys_glob), else: opts
      opts = if tftp != "", do: Map.put(opts, :tftp_server, tftp), else: opts
      opts = Map.put(opts, :force?, force)

      case RuleMatcher.plan_upgrades_multi(selected, opts) do
        {:ok, plan} ->
          case do_action do
            "run" ->
              {:ok, results} =
                RuleMatcher.apply_plan_multi(plan,
                  concurrency: 6,
                  poll_ms: 300,
                  poll_attempts: 50
                )

              {:noreply,
               socket
               |> assign(:mac_rule, mac_rule)
               |> assign(:sys_glob, sys_glob)
               |> assign(:firmware_file, fw_file)
               |> assign(:tftp_server, tftp)
               |> assign(:error, nil)
               |> assign(:preview, plan)
               |> assign(:results, results)
               |> assign(:force, force)
               |> put_flash(:info, "Upgrade plan executing; results updated.")}

            _ ->
              {:noreply,
               socket
               |> assign(:mac_rule, mac_rule)
               |> assign(:sys_glob, sys_glob)
               |> assign(:firmware_file, fw_file)
               |> assign(:tftp_server, tftp)
               |> assign(:error, nil)
               |> assign(:preview, plan)
               |> assign(:results, [])
               |> assign(:force, force)}
          end

        {:error, reason} ->
          {:noreply, assign(socket, error: inspect(reason), preview: [], results: [])}
      end
    end
  end

  @impl true
  def handle_event("run", _params, socket) do
    {:ok, results} =
      RuleMatcher.apply_plan_multi(socket.assigns.preview,
        concurrency: 6,
        poll_ms: 300,
        poll_attempts: 50
      )

    {:noreply,
     assign(socket, results: results)
     |> put_flash(:info, "Upgrade plan executing; results updated.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Manual Upgrades
        <:subtitle>
          Ad-hoc upgrades with preview/dry-run. Validate your criteria here; to persist as a scheduled rule, add it on the Rules page.
        </:subtitle>
      </.header>

      <div class="bg-gray-800 rounded-lg shadow-md p-6">
        <h3 class="text-md font-semibold text-gray-100 mb-3">Target</h3>
        <p class="text-sm text-gray-300">
          Rules apply globally across all known CMTS sources. No selection is required.
        </p>
        <p class="text-xs text-gray-400 mt-2">
          Tip: After a successful dry-run here, create a persistent scheduled rule on the
          <a href="/upgrade_rules" class="text-indigo-400 hover:text-indigo-300">Rules</a>
          page.
        </p>
      </div>

      <div class="bg-gray-800 rounded-lg shadow-md p-6">
        <h3 class="text-md font-semibold text-gray-100 mb-3">Rules</h3>
        <form phx-submit="preview" class="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div>
            <label class="block text-sm text-gray-300">MAC Rule</label>
            <input
              name="mac_rule"
              value={@mac_rule}
              placeholder="aa:bb:cc:00:00:00/24"
              class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100"
            />
          </div>
          <div>
            <label class="block text-sm text-gray-300">sysDescr Glob</label>
            <input
              name="sysdescr_glob"
              value={@sys_glob}
              placeholder="%Arris%5.9.3%"
              class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100"
            />
          </div>
          <div>
            <label class="block text-sm text-gray-300">Firmware File</label>
            <input
              name="firmware_file"
              value={@firmware_file}
              required
              placeholder="vendor-fw.bin"
              class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100"
            />
          </div>
          <div>
            <label class="block text-sm text-gray-300">TFTP Server</label>
            <input
              name="tftp_server"
              value={@tftp_server}
              placeholder="10.0.0.5"
              class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100"
            />
          </div>
          <div class="flex items-center gap-3 md:col-span-4">
            <label class="inline-flex items-center text-sm text-gray-300">
              <input
                type="checkbox"
                name="force"
                value="true"
                checked={@force}
                class="rounded border-gray-600 bg-gray-700 text-indigo-600 focus:ring-indigo-500"
              />
              <span class="ml-2">Force run (ignore already upgraded)</span>
            </label>
            <div class="grow"></div>
            <button
              type="submit"
              name="do"
              value="preview"
              class="px-3 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-md text-sm"
            >
              Preview Plan (Dry Run)
            </button>
            <button
              type="submit"
              name="do"
              value="run"
              class="px-3 py-2 bg-green-600 hover:bg-green-700 text-white rounded-md text-sm"
            >
              Run Now
            </button>
          </div>
        </form>
        <p class="mt-3 text-xs text-gray-400">
          Note: To prevent repeated upgrades, devices already upgraded to the same firmware (based on MAC + firmware) are skipped automatically. Enable "Force run" to override this behavior for a one-off execution.
        </p>
        <%= if @error do %>
          <div class="text-sm text-red-400 mt-2">Error: {@error}</div>
        <% end %>
      </div>

      <div class="bg-gray-800 rounded-lg shadow-md p-6">
        <h3 class="text-md font-semibold text-gray-100 mb-3">Preview</h3>
        <%= if Enum.any?(@preview) do %>
          <table class="w-full text-sm">
            <thead class="text-left text-gray-400">
              <tr>
                <th class="py-2">CMTS</th>
                <th class="py-2">MAC</th>
                <th class="py-2">IP</th>
                <th class="py-2">Port</th>
                <th class="py-2">sysDescr</th>
                <th class="py-2">Firmware</th>
                <th class="py-2">TFTP</th>
              </tr>
            </thead>
            <tbody class="text-gray-200 divide-y divide-gray-700">
              <%= for p <- @preview do %>
                <tr>
                  <td class="py-2">{p[:cmts_id]}</td>
                  <td class="py-2">{p.mac}</td>
                  <td class="py-2">{p.ip}</td>
                  <td class="py-2">{p.port}</td>
                  <td class="py-2 truncate max-w-xs" title={p.sysdescr}>{p.sysdescr}</td>
                  <td class="py-2">{p.firmware_file}</td>
                  <td class="py-2">{p.tftp_server}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <div class="mt-3 flex justify-end">
            <button
              phx-click="run"
              class="px-3 py-2 bg-green-600 hover:bg-green-700 text-white rounded-md text-sm"
            >
              Run Plan
            </button>
          </div>
        <% else %>
          <div class="text-sm text-gray-400">No devices matched the current rules.</div>
        <% end %>
      </div>

      <%= if Enum.any?(@results) do %>
        <div class="bg-gray-800 rounded-lg shadow-md p-6">
          <h3 class="text-md font-semibold text-gray-100 mb-3">Results</h3>
          <ul class="text-sm text-gray-200 space-y-1">
            <%= for r <- @results do %>
              <li>{r.mac} — {inspect(r.result)} ({r.final_status})</li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
    """
  end
end
