defmodule FirmwareManagerWeb.UpgradeRuleLive.Index do
  use FirmwareManagerWeb, :live_view
  alias FirmwareManager.UpgradeAPI
  alias FirmwareManager.UpgradeRules.Rule

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:rules, [])
     |> assign(:page_title, "Upgrade Rules")
     |> assign(:rule, %Rule{})
     |> assign(:changeset, nil)
     |> assign(:scheduler_enabled, FirmwareManager.UpgradeBoot.enabled?())
     |> assign(:scheduler_interval_secs, div(FirmwareManager.UpgradeBoot.get_interval_ms(), 1000))
     |> load_rules()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Upgrade Rules")
    |> assign(:rule, %Rule{})
    |> assign(:changeset, nil)
    |> load_rules()
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Rule")
    |> assign(:rule, %Rule{})
    |> assign(:changeset, nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    rule = UpgradeAPI.get_rule!(id)

    socket
    |> assign(:page_title, "Edit Rule")
    |> assign(:rule, rule)
    |> assign(:changeset, nil)
  end

  defp load_rules(socket) do
    rules = UpgradeAPI.list_rules() |> Enum.map(&Map.from_struct/1)
    assign(socket, :rules, rules)
  end

  @impl true
  def handle_event("save", %{"rule" => params}, socket) do
    mode = if socket.assigns.live_action == :edit, do: :edit, else: :new
    attrs = sanitize_rule_params(params)
    save_rule(socket, mode, attrs)
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    rule = UpgradeAPI.get_rule!(id)
    {:ok, _} = UpgradeAPI.update_rule(rule, %{enabled: !rule.enabled})
    {:noreply, load_rules(socket)}
  end

  @impl true
  def handle_event("run", %{"id" => id}, socket) do
    # Shallow integration: push to Upgrades planner with prefilled params via redirect
    rule = UpgradeAPI.get_rule!(id)

    params = %{
      "mac_rule" => rule.mac_rule || "",
      "sysdescr_glob" => rule.sysdescr_glob || "",
      "firmware_file" => rule.firmware_file || "",
      "tftp_server" => rule.tftp_server || "",
      "rule_id" => rule.id,
      "do" => "run"
    }

    {:noreply, push_navigate(socket, to: ~p"/upgrades?#{params}")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    rule = UpgradeAPI.get_rule!(id)
    {:ok, _} = UpgradeAPI.delete_rule(rule)
    {:noreply, socket |> put_flash(:info, "Rule deleted") |> load_rules()}
  end

  @impl true
  def handle_event("scheduler_toggle", _params, socket) do
    enabled = socket.assigns.scheduler_enabled

    if enabled,
      do: FirmwareManager.UpgradeBoot.disable(),
      else: FirmwareManager.UpgradeBoot.enable()

    {:noreply,
     assign(socket, :scheduler_enabled, !enabled)
     |> put_flash(:info, "Scheduler #{if(enabled, do: "disabled", else: "enabled")}.")}
  end

  @impl true
  def handle_event("scheduler_interval", %{"interval_secs" => secs}, socket) do
    secs_int =
      case Integer.parse(to_string(secs)) do
        {i, _} when i > 0 -> i
        _ -> socket.assigns.scheduler_interval_secs
      end

    ms = secs_int * 1000
    :ok = FirmwareManager.UpgradeBoot.set_interval_ms(ms)

    {:noreply,
     assign(socket, :scheduler_interval_secs, secs_int)
     |> put_flash(:info, "Scheduler interval updated.")}
  end

  defp save_rule(socket, :new, params) do
    case UpgradeAPI.create_rule(params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rule created")
         |> push_patch(to: ~p"/upgrade_rules")
         |> load_rules()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           error_message(
             changeset,
             "Invalid rule: please fill required fields (name, firmware_file)"
           )
         )}
    end
  end

  defp save_rule(socket, :edit, params) do
    case UpgradeAPI.update_rule(socket.assigns.rule, params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rule updated")
         |> push_patch(to: ~p"/upgrade_rules")
         |> load_rules()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           error_message(
             changeset,
             "Invalid rule: please fill required fields (name, firmware_file)"
           )
         )}
    end
  end

  # Convert string params from the form into the atom-keyed attrs Ash expects.
  defp sanitize_rule_params(params) when is_map(params) do
    %{
      name: Map.get(params, "name"),
      description: blank_to_nil(Map.get(params, "description")),
      mac_rule: blank_to_nil(Map.get(params, "mac_rule")),
      sysdescr_glob: blank_to_nil(Map.get(params, "sysdescr_glob")),
      firmware_file: Map.get(params, "firmware_file"),
      tftp_server: blank_to_nil(Map.get(params, "tftp_server")),
      enabled: truthy?(Map.get(params, "enabled"))
    }
    |> Enum.reject(fn {_k, v} -> v == :absent end)
    |> Map.new()
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp truthy?(v) when is_binary(v), do: v in ["true", "on", "1", "yes"]
  defp truthy?(true), do: true
  defp truthy?(_), do: false

  defp error_message(%Ecto.Changeset{} = changeset, fallback) do
    errs =
      changeset.errors
      |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
      |> Enum.join(", ")

    if errs == "", do: fallback, else: "Invalid rule: " <> errs
  end

  defp error_message(_changeset, fallback), do: fallback

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.header>
        Upgrade Rules
        <:subtitle>
          Persisted rules applied globally. Enable/disable, run now, or create/edit.
        </:subtitle>
        <:actions>
          <div class="flex items-center gap-2">
            <form phx-submit="scheduler_interval" class="flex items-center gap-2">
              <label class="text-sm text-gray-300">Interval (s)</label>
              <input
                name="interval_secs"
                value={@scheduler_interval_secs}
                class="w-24 rounded-md border-gray-600 bg-gray-700 text-gray-100 text-sm"
              />
              <button
                type="submit"
                class="px-2 py-1 bg-zinc-700 hover:bg-zinc-600 text-white rounded text-xs"
              >
                Update
              </button>
            </form>
            <button
              phx-click="scheduler_toggle"
              class={"px-2 py-1 rounded text-xs " <> if(@scheduler_enabled, do: "bg-green-700", else: "bg-gray-700")}
            >
              {if @scheduler_enabled, do: "Scheduler: ON", else: "Scheduler: OFF"}
            </button>
            <.link
              patch={if @live_action == :new, do: ~p"/upgrade_rules", else: ~p"/upgrade_rules/new"}
              class="px-3 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-md text-sm"
            >
              {if @live_action == :new, do: "Close", else: "New Rule"}
            </.link>
          </div>
        </:actions>
      </.header>

      <p class="text-xs text-gray-400">
        Note: The scheduler and manual runs skip devices that have already been upgraded to the same firmware (MAC + firmware). Use the Upgrades Planner's "Force run" to override when needed.
      </p>
      <p class="text-xs text-gray-400">
        Tip: Validate your matching criteria on the
        <a href="/upgrades" class="text-indigo-400 hover:text-indigo-300">Manual Upgrades</a>
        page with a dry-run, then add it here as a persistent rule.
      </p>

      <%= if (@live_action in [:new, :edit]) do %>
        <div class="bg-gray-800 rounded-lg shadow p-6">
          <form id="rule-form" phx-submit="save" class="space-y-4">
            <div>
              <label class="block text-sm text-gray-300">Name</label>
              <input
                name="rule[name]"
                value={@rule.name || ""}
                required
                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100"
              />
            </div>
            <div>
              <label class="block text-sm text-gray-300">Description</label>
              <textarea
                name="rule[description]"
                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100"
              ><%= @rule.description || "" %></textarea>
            </div>
            <div>
              <label class="block text-sm text-gray-300">MAC Rule</label>
              <input
                name="rule[mac_rule]"
                value={@rule.mac_rule || ""}
                placeholder="aa:bb:cc:00:00:00/24"
                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100"
              />
            </div>
            <div>
              <label class="block text-sm text-gray-300">sysDescr Glob</label>
              <input
                name="rule[sysdescr_glob]"
                value={@rule.sysdescr_glob || ""}
                placeholder="%Arris%5.9.3%"
                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100"
              />
            </div>
            <div>
              <label class="block text-sm text-gray-300">Firmware File</label>
              <input
                name="rule[firmware_file]"
                value={@rule.firmware_file || ""}
                required
                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100"
              />
            </div>
            <div>
              <label class="block text-sm text-gray-300">TFTP Server</label>
              <input
                name="rule[tftp_server]"
                value={@rule.tftp_server || ""}
                placeholder="10.0.0.5"
                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-gray-100"
              />
            </div>
            <div class="flex items-center">
              <input
                type="checkbox"
                name="rule[enabled]"
                value="true"
                checked={@rule.enabled}
                class="rounded border-gray-600 bg-gray-700 text-indigo-600 focus:ring-indigo-500"
              />
              <span class="ml-2 text-sm text-gray-300">Enabled</span>
            </div>
            <div class="pt-2 flex items-center gap-2">
              <button
                type="submit"
                class="px-3 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-md text-sm"
              >
                Save Rule
              </button>
              <.link patch={~p"/upgrade_rules"} class="text-sm text-gray-300 hover:text-gray-100">
                Cancel
              </.link>
            </div>
          </form>
        </div>
      <% end %>

      <div class="bg-gray-800 rounded-lg shadow p-6">
        <h3 class="text-md font-semibold text-gray-100 mb-3">Existing Rules</h3>
        <%= if Enum.empty?(@rules) do %>
          <div class="text-gray-400 text-sm">No rules yet. Create one.</div>
        <% else %>
          <table class="w-full text-sm">
            <thead class="text-left text-gray-400">
              <tr>
                <th class="py-2">Name</th>
                <th class="py-2">MAC Rule</th>
                <th class="py-2">sysDescr Glob</th>
                <th class="py-2">Firmware</th>
                <th class="py-2">TFTP</th>
                <th class="py-2">Enabled</th>
                <th class="py-2"></th>
              </tr>
            </thead>
            <tbody class="text-gray-200 divide-y divide-gray-700">
              <%= for rule <- @rules do %>
                <tr id={"rule-#{rule.id}"}>
                  <td class="py-2">
                    <div class="font-medium">{rule.name}</div>
                    <div class="text-xs text-gray-400 truncate max-w-xs">{rule.description}</div>
                  </td>
                  <td class="py-2">{rule.mac_rule}</td>
                  <td class="py-2 truncate max-w-xs" title={rule.sysdescr_glob}>
                    {rule.sysdescr_glob}
                  </td>
                  <td class="py-2">{rule.firmware_file}</td>
                  <td class="py-2">{rule.tftp_server}</td>
                  <td class="py-2">
                    <button
                      phx-click="toggle"
                      phx-value-id={rule.id}
                      class={"px-2 py-1 rounded text-xs " <> if(rule.enabled, do: "bg-green-700", else: "bg-gray-700") }
                    >
                      {if rule.enabled, do: "Enabled", else: "Disabled"}
                    </button>
                  </td>
                  <td class="py-2 text-right">
                    <.link
                      patch={~p"/upgrade_rules/#{rule.id}/edit"}
                      class="px-2 py-1 bg-zinc-700 hover:bg-zinc-600 text-white rounded text-xs"
                    >
                      Edit
                    </.link>
                    <button
                      phx-click="run"
                      phx-value-id={rule.id}
                      class="ml-2 px-2 py-1 bg-indigo-700 hover:bg-indigo-600 text-white rounded text-xs"
                    >
                      Run Now
                    </button>
                    <button
                      phx-click="delete"
                      phx-value-id={rule.id}
                      data-confirm="Are you sure?"
                      class="ml-2 px-2 py-1 bg-red-700 hover:bg-red-600 text-white rounded text-xs"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    </div>
    """
  end
end
