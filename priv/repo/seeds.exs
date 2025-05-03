# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     FirmwareManager.Repo.insert!(%FirmwareManager.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias FirmwareManager.Modem.UpgradeLog
alias FirmwareManager.Repo

# Function to generate a random MAC address
random_mac_address = fn ->
  Enum.map_join(1..6, ":", fn _ ->
    Integer.to_string(:rand.uniform(255), 16)
    |> String.pad_leading(2, "0")
    |> String.downcase()
  end)
end

# Function to generate a random firmware version
random_firmware_version = fn ->
  major = :rand.uniform(5) - 1
  minor = :rand.uniform(9)
  patch = :rand.uniform(9)
  "#{major}.#{minor}.#{patch}"
end

# Function to generate a newer firmware version based on an existing one
random_newer_firmware_version = fn version ->
  [major, minor, patch] = String.split(version, ".")
  {major, _} = Integer.parse(major)
  {minor, _} = Integer.parse(minor)
  {patch, _} = Integer.parse(patch)

  # Randomly decide which version component to increment
  case :rand.uniform(3) do
    1 -> "#{major + 1}.#{minor}.#{patch}"
    2 -> "#{major}.#{minor + 1}.#{patch}"
    3 -> "#{major}.#{minor}.#{patch + 1}"
  end
end

# Function to generate a random date within the specified number of months from now
random_date_within_months = fn months ->
  now = DateTime.utc_now()
  seconds_in_month = 30 * 24 * 60 * 60
  max_seconds_ago = months * seconds_in_month
  random_seconds_ago = :rand.uniform(max_seconds_ago)

  now
  |> DateTime.add(-random_seconds_ago, :second)
  |> DateTime.truncate(:second)
end

# Generate 25 sample upgrade logs
IO.puts("\nGenerating sample upgrade logs...")

# Use direct SQL insertion for simplicity
for _ <- 1..2500 do
  mac_address = random_mac_address.()
  old_version = random_firmware_version.()
  new_version = random_newer_firmware_version.(old_version)
  # Generate longer sysdescr values to test truncation
  vendor = Enum.random(["Cisco", "Arris", "Motorola", "Technicolor", "Ubee", "Netgear"])
  model = "#{Enum.random(["DPC", "SB", "CGM", "SVG", "TG"])}#{:rand.uniform(4000)}"
  build = "#{:rand.uniform(100)}.#{:rand.uniform(100)}.#{:rand.uniform(100)}"
  chip = Enum.random(["Broadcom BCM3390", "Intel Puma 7", "MediaTek MT7621", "Qualcomm IPQ8074"])
  features = Enum.random([
    "DOCSIS 3.1, 2x2 OFDM/OFDMA",
    "DOCSIS 3.0, 32x8 Channel Bonding",
    "DOCSIS 3.1, 2x2 OFDM/OFDMA with Full Duplex",
    "DOCSIS 3.0, 24x8 Channel Bonding with Voice"
  ])

  old_sysdescr = "#{vendor} #{model} Modem System #{old_version}, Hardware Rev. #{:rand.uniform(5)}, Build #{build}, #{chip}, #{features}, MAC #{random_mac_address.()}"
  new_sysdescr = "#{vendor} #{model} Modem System #{new_version}, Hardware Rev. #{:rand.uniform(5)}, Build #{build}, #{chip}, #{features}, MAC #{random_mac_address.()}"

  upgraded_at = random_date_within_months.(6)

  # Insert directly using Repo
  Repo.insert!(%UpgradeLog{
    id: Ecto.UUID.generate(),
    mac_address: mac_address,
    old_sysdescr: old_sysdescr,
    new_sysdescr: new_sysdescr,
    new_firmware: new_version,
    upgraded_at: upgraded_at
  })
end

IO.puts("\n✅ Created 2500 sample upgrade logs")
