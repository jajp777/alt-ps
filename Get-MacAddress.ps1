function Get-MacAddress {
  [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
  Where-Object {
    $_.OperationalStatus -eq [Net.NetworkInformation.OperationalStatus]::Up
  } | ForEach-Object {
    if (![String]::IsNullOrEmpty((
      $$ = $_.GetPhysicalAddress().ToString()
    ))) {
      New-Object PSObject -Property @{
        Description = $_.Description
        Id          = $_.Id
        MACAddress  = [Regex]::Replace($$, '.{2}', '$0-').TrimEnd('-')
      }
    }
  } | Select-Object Description, Id, MACAddress | Format-List
}
