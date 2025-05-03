defmodule FirmwareManagerWeb.FirmwareManagerWeb.UpgradeLogLive.FormComponent do
  use FirmwareManagerWeb, :live_component

  alias FirmwareManager.Modem

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage upgrade_log records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="upgrade_log-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:mac_address]} type="text" label="Mac address" />
        <.input field={@form[:old_sysdescr]} type="text" label="Old sysdescr" />
        <.input field={@form[:new_sysdescr]} type="text" label="New sysdescr" />
        <.input field={@form[:new_firmware]} type="text" label="New firmware" />
        <.input field={@form[:upgraded_at]} type="datetime-local" label="Upgraded at" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Upgrade log</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{upgrade_log: upgrade_log} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Modem.change_upgrade_log(upgrade_log))
     end)}
  end

  @impl true
  def handle_event("validate", %{"upgrade_log" => upgrade_log_params}, socket) do
    changeset = Modem.change_upgrade_log(socket.assigns.upgrade_log, upgrade_log_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"upgrade_log" => upgrade_log_params}, socket) do
    save_upgrade_log(socket, socket.assigns.action, upgrade_log_params)
  end

  defp save_upgrade_log(socket, :edit, upgrade_log_params) do
    case Modem.update_upgrade_log(socket.assigns.upgrade_log, upgrade_log_params) do
      {:ok, upgrade_log} ->
        notify_parent({:saved, upgrade_log})

        {:noreply,
         socket
         |> put_flash(:info, "Upgrade log updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_upgrade_log(socket, :new, upgrade_log_params) do
    case Modem.create_upgrade_log(upgrade_log_params) do
      {:ok, upgrade_log} ->
        notify_parent({:saved, upgrade_log})

        {:noreply,
         socket
         |> put_flash(:info, "Upgrade log created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
