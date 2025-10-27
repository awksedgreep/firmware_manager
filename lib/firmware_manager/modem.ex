defmodule FirmwareManager.Modem do
  @moduledoc "Context for Modem-related resources (Ecto)."

  import Ecto.Query
  alias FirmwareManager.Repo
  alias FirmwareManager.Modem.{UpgradeLog, Cmts}

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

    base = from(u in UpgradeLog)

    query =
      case test_id do
        nil -> base
        id -> from(u in base, where: u.id == ^id)
      end

    query =
      Enum.reduce(filter_conditions, query, fn {field, value}, acc ->
        from(u in acc, where: field(u, ^field) == ^value)
      end)

    sort_direction = Keyword.get(opts, :sort, :desc)
    sort_by = Keyword.get(opts, :sort_by, :upgraded_at)

    query =
      case sort_by do
        :mac_address -> from(u in query, order_by: [{^sort_direction, u.mac_address}])
        :old_sysdescr -> from(u in query, order_by: [{^sort_direction, u.old_sysdescr}])
        :new_sysdescr -> from(u in query, order_by: [{^sort_direction, u.new_sysdescr}])
        :new_firmware -> from(u in query, order_by: [{^sort_direction, u.new_firmware}])
        :upgraded_at -> from(u in query, order_by: [{^sort_direction, u.upgraded_at}])
        _ -> from(u in query, order_by: [desc: u.upgraded_at])
      end

    query = if offset > 0, do: from(u in query, offset: ^offset), else: query

    query =
      case limit do
        :infinity -> query
        n when is_integer(n) -> from(u in query, limit: ^n)
        _ -> query
      end

    Repo.all(query)
  end

  # The list_upgrade_logs/1 function is already defined above with a default parameter

  @doc """
  Gets a single upgrade_log.

  Raises if the Upgrade log does not exist.

  ## Examples

      iex> get_upgrade_log!(123)
      %UpgradeLog{}

  """
  def get_upgrade_log!(id), do: Repo.get!(UpgradeLog, id)

  @doc """
  Creates a upgrade_log.

  ## Examples

      iex> create_upgrade_log(%{field: value})
      {:ok, %UpgradeLog{}}

      iex> create_upgrade_log(%{field: bad_value})
      {:error, ...}

  """
  def create_upgrade_log(attrs \\ %{}) do
    %UpgradeLog{}
    |> UpgradeLog.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns true if there exists a log entry for the given MAC upgraded to the given firmware.
  """
  @spec upgrade_log_exists?(String.t(), String.t()) :: boolean()
  def upgrade_log_exists?(mac, firmware) when is_binary(mac) and is_binary(firmware) do
    from(u in UpgradeLog, where: u.mac_address == ^mac and u.new_firmware == ^firmware, select: 1)
    |> Repo.exists?()
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
    Repo.delete_all(UpgradeLog)
  end

  @doc """
  Deletes upgrade logs older than the given cutoff datetime.
  """
  @spec delete_old_upgrade_logs(DateTime.t()) :: {integer(), nil}
  def delete_old_upgrade_logs(%DateTime{} = cutoff) do
    from(u in UpgradeLog, where: u.upgraded_at < ^cutoff)
    |> Repo.delete_all()
  end

  # CMTS CRUD Operations

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

    base = from(c in Cmts)

    query =
      Enum.reduce(filter_conditions, base, fn {field, value}, acc ->
        from(c in acc, where: field(c, ^field) == ^value)
      end)

    sort_direction = Keyword.get(opts, :sort, :asc)
    sort_by = Keyword.get(opts, :sort_by, :ip)

    query =
      case sort_by do
        :ip -> from(c in query, order_by: [{^sort_direction, c.ip}])
        :snmp_read -> from(c in query, order_by: [{^sort_direction, c.snmp_read}])
        :modem_snmp_read -> from(c in query, order_by: [{^sort_direction, c.modem_snmp_read}])
        :modem_snmp_write -> from(c in query, order_by: [{^sort_direction, c.modem_snmp_write}])
        :inserted_at -> from(c in query, order_by: [{^sort_direction, c.inserted_at}])
        :updated_at -> from(c in query, order_by: [{^sort_direction, c.updated_at}])
        _ -> from(c in query, order_by: [asc: c.ip])
      end

    query = if offset > 0, do: from(c in query, offset: ^offset), else: query

    query =
      case limit do
        :infinity -> query
        n when is_integer(n) -> from(c in query, limit: ^n)
        _ -> query
      end

    Repo.all(query)
  end

  alias FirmwareManager.Modem.Cmts

  @doc """
  Gets a single CMTS.

  Raises if the CMTS does not exist.

  ## Examples

      iex> get_cmts!("123e4567-e89b-12d3-a456-426614174000")
      %Cmts{}

  """
  def get_cmts!(id), do: Repo.get!(Cmts, id)

  @doc """
  Creates a CMTS.

  ## Examples

      iex> create_cmts(%{field: value})
      {:ok, %Cmts{}}

      iex> create_cmts(%{field: bad_value})
      {:error, ...}

  """
  def create_cmts(attrs \\ %{}) do
    %Cmts{}
    |> Cmts.create_changeset(attrs)
    |> Repo.insert()
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
    |> Cmts.update_changeset(attrs)
    |> Repo.update()
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
    Repo.delete(cmts)
  end

  @doc """
  Returns a data structure for tracking CMTS changes.

  ## Examples

      iex> change_cmts(cmts)
      %Todo{...}

  """
  def change_cmts(%Cmts{} = cmts, attrs \\ %{}) do
    Cmts.update_changeset(cmts, attrs)
  end
end
