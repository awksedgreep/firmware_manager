defmodule FirmwareManager.Modem do
  @moduledoc "Domain for Modem-related resources."

  require Ash.Query
  import Ash.Expr

  use Ash.Domain,
    otp_app: :firmware_manager,
    validate_config_inclusion?: false

  resources do
    resource FirmwareManager.Modem.UpgradeLog
    resource FirmwareManager.Modem.Cmts
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
    test_id = Keyword.get(opts, :id)
    
    query = FirmwareManager.Modem.UpgradeLog
    
    # If a specific ID is provided (for tests), only return that record
    query = if test_id do
      Ash.Query.filter(query, id == ^test_id)
    else
      query
    end
    
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

  # The list_upgrade_logs/1 function is already defined above with a default parameter

  @doc """
  Gets a single upgrade_log.

  Raises if the Upgrade log does not exist.

  ## Examples

      iex> get_upgrade_log!(123)
      %UpgradeLog{}

  """
  def get_upgrade_log!(id) do
    result = FirmwareManager.Modem.UpgradeLog
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one()
    
    case result do
      {:ok, record} -> record
      {:error, _} -> raise Ecto.NoResultsError, queryable: FirmwareManager.Modem.UpgradeLog
    end
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
  Returns true if there exists a log entry for the given MAC upgraded to the given firmware.
  """
  @spec upgrade_log_exists?(String.t(), String.t()) :: boolean()
  def upgrade_log_exists?(mac, firmware) when is_binary(mac) and is_binary(firmware) do
    FirmwareManager.Modem.UpgradeLog
    |> Ash.Query.filter(mac_address == ^mac and new_firmware == ^firmware)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> case do
      [] -> false
      _ -> true
    end
  end

  # Note: Individual update and delete functions are intentionally not implemented
  # since logs are immutable records of historical events.
  # Only bulk deletion is supported via the delete_all_upgrade_logs function
  # which is used by the "Truncate Logs" button in the UI.

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

  @doc """
  Deletes upgrade logs older than the given cutoff datetime.
  """
  @spec delete_old_upgrade_logs(DateTime.t()) :: {integer(), nil}
  import Ecto.Query, only: [from: 2]

  def delete_old_upgrade_logs(%DateTime{} = cutoff) do
    FirmwareManager.Modem.UpgradeLog
    |> Ash.Query.filter(upgraded_at < ^cutoff)
    |> Ash.destroy!()
  end

  # CMTS CRUD Operations

  @doc """
  Lists all CMTS entries.

  ## Options

  * `:limit` - Limit the number of results (default: 100)
  * `:sort` - Sort direction, can be `:asc` or `:desc` (default: `:asc`)
  * `:sort_by` - Field to sort by (default: `:ip`)
  * `:filter` - A filter to apply to the query

  ## Examples

      # Get all CMTS entries
      FirmwareManager.Modem.list_cmts()

      # Get CMTS entries with a specific IP
      FirmwareManager.Modem.list_cmts(filter: [ip: "192.168.1.1"])
  """
  def list_cmts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    filter_conditions = Keyword.get(opts, :filter, [])
    
    query = FirmwareManager.Modem.Cmts
    
    # Apply filter if provided
    query = Enum.reduce(filter_conditions, query, fn {field, value}, acc ->
      Ash.Query.filter(acc, expr(^ref(field) == ^value))
    end)
    
    # Apply sorting if specified
    query = if Keyword.has_key?(opts, :sort) or Keyword.has_key?(opts, :sort_by) do
      sort_direction = Keyword.get(opts, :sort, :asc)
      sort_by = Keyword.get(opts, :sort_by, :ip)
      
      # Handle different field names appropriately
      case sort_by do
        :ip -> Ash.Query.sort(query, ip: sort_direction)
        :snmp_read -> Ash.Query.sort(query, snmp_read: sort_direction)
        :modem_snmp_read -> Ash.Query.sort(query, modem_snmp_read: sort_direction)
        :modem_snmp_write -> Ash.Query.sort(query, modem_snmp_write: sort_direction)
        :inserted_at -> Ash.Query.sort(query, inserted_at: sort_direction)
        :updated_at -> Ash.Query.sort(query, updated_at: sort_direction)
        _ -> 
          # Default to IP if an unsupported sort field is provided
          Ash.Query.sort(query, ip: :asc)
      end
    else
      # Default sort by IP ascending
      Ash.Query.sort(query, ip: :asc)
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

  alias FirmwareManager.Modem.Cmts

  @doc """
  Gets a single CMTS.

  Raises if the CMTS does not exist.

  ## Examples

      iex> get_cmts!("123e4567-e89b-12d3-a456-426614174000")
      %Cmts{}

  """
  def get_cmts!(id) do
    FirmwareManager.Modem.Cmts
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one!()
  end

  @doc """
  Creates a CMTS.

  ## Examples

      iex> create_cmts(%{field: value})
      {:ok, %Cmts{}}

      iex> create_cmts(%{field: bad_value})
      {:error, ...}

  """
  def create_cmts(attrs \\ %{}) do
    FirmwareManager.Modem.Cmts
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  @doc """
  Updates a CMTS.

  ## Examples

      iex> update_cmts(cmts, %{field: new_value})
      {:ok, %Cmts{}}

      iex> update_cmts(cmts, %{field: bad_value})
      {:error, ...}

  """
  def update_cmts(%Cmts{} = cmts, attrs) do
    cmts
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update()
  end

  @doc """
  Deletes a CMTS.

  ## Examples

      iex> delete_cmts(cmts)
      {:ok, %Cmts{}}

      iex> delete_cmts(cmts)
      {:error, ...}

  """
  def delete_cmts(%Cmts{} = cmts) do
    cmts
    |> Ash.Changeset.for_destroy(:destroy)
    |> Ash.destroy()
  end

  @doc """
  Returns a data structure for tracking CMTS changes.

  ## Examples

      iex> change_cmts(cmts)
      %Todo{...}

  """
  def change_cmts(%Cmts{} = cmts, attrs \\ %{}) do
    cmts
    |> Ash.Changeset.for_update(:update, attrs)
  end
end
