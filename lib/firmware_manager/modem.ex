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
        :upgraded_at -> Ash.Query.sort(query, upgraded_at: sort_direction)
        _ -> 
          # Default to upgraded_at if an unsupported sort field is provided
          Ash.Query.sort(query, upgraded_at: :desc)
      end
    else
      # Default sort by upgraded_at descending
      Ash.Query.sort(query, upgraded_at: :desc)
    end
    
    # Apply limit
    query = Ash.Query.limit(query, limit)
    
    # Execute the query
    Ash.read!(query)
  end
end
