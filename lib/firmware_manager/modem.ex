defmodule FirmwareManager.Modem do
  @moduledoc "Domain for Modem-related resources."

  require Ash.Query
  import Ash.Expr

  use Ash.Domain,
    otp_app: :firmware_manager,
    validate_config_inclusion?: false

  resources do
    resource FirmwareManager.Modem.UpgradeLog
  end

  @doc """
  Lists all upgrade logs.
  
  ## Options
  
  * `:limit` - Limit the number of results (default: 100)
  * `:sort` - Sort direction, can be `:asc` or `:desc` (default: `:desc`)
  * `:sort_by` - Field to sort by (default: `:upgraded_at`)
  * `:filter` - A filter to apply to the query
  
  ## Examples
  
      # Get all upgrade logs
      FirmwareManager.Modem.list_upgrade_logs()
      
      # Get the 10 most recent upgrade logs
      FirmwareManager.Modem.list_upgrade_logs(limit: 10)
      
      # Get upgrade logs for a specific MAC address
      FirmwareManager.Modem.list_upgrade_logs(filter: [mac_address: "00:11:22:33:44:55"])
  """
  def list_upgrade_logs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    filter_conditions = Keyword.get(opts, :filter, [])
    
    query = FirmwareManager.Modem.UpgradeLog
    
    # Apply filter if provided
    query = Enum.reduce(filter_conditions, query, fn {field, value}, acc ->
      Ash.Query.filter(acc, expr(^ref(field) == ^value))
    end)
    
    # Apply sorting if specified
    query = if Keyword.has_key?(opts, :sort) or Keyword.has_key?(opts, :sort_by) do
      sort_direction = Keyword.get(opts, :sort, :desc)
      sort_by = Keyword.get(opts, :sort_by, :upgraded_at)
      
      # Handle different field names appropriately
      case sort_by do
        :mac_address -> Ash.Query.sort(query, mac_address: sort_direction)
        :old_sysdescr -> Ash.Query.sort(query, old_sysdescr: sort_direction)
        :new_sysdescr -> Ash.Query.sort(query, new_sysdescr: sort_direction)
        :new_firmware -> Ash.Query.sort(query, new_firmware: sort_direction)
        :upgraded_at -> Ash.Query.sort(query, upgraded_at: sort_direction)
        _ -> 
          # Default to upgraded_at if an unsupported sort field is provided
          Ash.Query.sort(query, upgraded_at: :desc)
      end
    else
      # Default sort by upgraded_at descending
      Ash.Query.sort(query, upgraded_at: :desc)
    end
    
    # Apply offset for pagination if provided
    query = if offset > 0 do
      Ash.Query.offset(query, offset)
    else
      query
    end
    
    # Apply limit unless it's :infinity
    query = case limit do
      :infinity -> query
      _ -> Ash.Query.limit(query, limit)
    end
    
    # Execute the query
    Ash.read!(query)
  end

  alias FirmwareManager.Modem.UpgradeLog

  # The list_upgrade_logs/1 function is already defined above with a default parameter

  @doc """
  Gets a single upgrade_log.

  Raises if the Upgrade log does not exist.

  ## Examples

      iex> get_upgrade_log!(123)
      %UpgradeLog{}

  """
  def get_upgrade_log!(id) do
    FirmwareManager.Modem.UpgradeLog
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one!()
  end

  @doc """
  Creates a upgrade_log.

  ## Examples

      iex> create_upgrade_log(%{field: value})
      {:ok, %UpgradeLog{}}

      iex> create_upgrade_log(%{field: bad_value})
      {:error, ...}

  """
  def create_upgrade_log(attrs \\ %{}) do
    FirmwareManager.Modem.UpgradeLog
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  @doc """
  Updates a upgrade_log.

  ## Examples

      iex> update_upgrade_log(upgrade_log, %{field: new_value})
      {:ok, %UpgradeLog{}}

      iex> update_upgrade_log(upgrade_log, %{field: bad_value})
      {:error, ...}

  """
  def update_upgrade_log(%UpgradeLog{} = upgrade_log, attrs) do
    upgrade_log
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update()
  end

  @doc """
  Deletes a UpgradeLog.

  ## Examples

      iex> delete_upgrade_log(upgrade_log)
      {:ok, %UpgradeLog{}}

      iex> delete_upgrade_log(upgrade_log)
      {:error, ...}

  """
  def delete_upgrade_log(%UpgradeLog{} = upgrade_log) do
    upgrade_log
    |> Ash.Changeset.for_destroy(:destroy)
    |> Ash.destroy()
  end

  @doc """
  Returns a data structure for tracking upgrade_log changes.

  ## Examples

      iex> change_upgrade_log(upgrade_log)
      %Todo{...}

  """
  def change_upgrade_log(%UpgradeLog{} = upgrade_log, attrs \\ %{}) do
    upgrade_log
    |> Ash.Changeset.for_update(:update, attrs)
  end

  @doc """
  Deletes all upgrade logs from the database.

  ## Examples

      iex> delete_all_upgrade_logs()
      {count, nil}

  Returns the number of records deleted.
  """
  @spec delete_all_upgrade_logs() :: {integer(), nil}
  def delete_all_upgrade_logs do
    # Use a direct SQL approach since we're deleting all records
    FirmwareManager.Repo.delete_all(FirmwareManager.Modem.UpgradeLog)
  end
end
