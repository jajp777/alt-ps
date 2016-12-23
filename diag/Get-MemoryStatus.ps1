function Get-MemoryStatus {
  <#
    .SYNOPSIS
        Retrieves information about the system's current usage of
        both physical and virtual memory.
    .NOTES
        Author: greg zakharov
  #>
  $MEMORYSTATUSEX = ($asm = [Object].Assembly).GetType(
    'Microsoft.Win32.Win32Native+MEMORYSTATUSEX'
  ).GetConstructor(
    [Reflection.BindingFlags]36, $null, [Type[]]@(), $null
  ).Invoke($null)
  
  if (!$asm.GetType(
    'Microsoft.Win32.Win32Native'
  ).GetMethod(
    'GlobalMemoryStatusEx', [Reflection.BindingFlags]40
  ).Invoke($null, @($MEMORYSTATUSEX))) {
    Write-Error 'could not retrieve memory status.'
    return
  }
  
  $MEMORYSTATUSEX.GetType().GetFields(
    [Reflection.BindingFlags]36
  ) | ForEach-Object {$table = @{}}{
    if ((
      $n = $_.Name -replace '\A\w', [Char]::ToUpper($_.Name[0])
    ) -ne 'Length' -and $n -notmatch 'extend') {
      $table[$n] = if ($n -match '\A(total|avail)') {
        "$(($_.GetValue($MEMORYSTATUSEX) / 1Gb).ToString('f3')) Gb"
      }
      elseif ($n -match 'load') {
        "$($_.GetValue($MEMORYSTATUSEX))%"
      }
    }
  }{ New-Object PSObject -Property $table }
}
