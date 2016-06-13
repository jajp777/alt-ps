function Get-Calendar {
  param(
    [Parameter(Position=0)]
    [Alias('m')]
    [ValidateRange(1, 12)]
    [Int32]$Month = (Get-Date -u %m),
    
    [Parameter(Position=1)]
    [Alias('y')]
    [ValidateRange(2000, 3000)]
    [Int32]$Year = (Get-Date -u %Y),
    
    [Parameter(Position=2)]
    [Alias('mf')]
    [Switch]$MondayFirst
  )
  
  begin {
    @(
      [Globalization.DateTimeFormatInfo],
      [Globalization.CultureInfo]
    ) | ForEach-Object {
      $keys = ($ta = [PSObject].Assembly.GetType(
        'System.Management.Automation.TypeAccelerators'
      ))::Get.Keys
    }{
      if ($keys -notcontains $_.Name) {
        $ta::Add($_.Name, $_)
      }
    }
    
    [DateTimeFormatInfo]::CurrentInfo.ShortestDayNames |
    ForEach-Object {$arr = @()}{$arr += $_}
    $cal = [CultureInfo]::CurrentCulture.Calendar
    $dow = [Int32]$cal.GetDayOfWeek([String]$Month + '.1.' + [String]$Year)

    if ($MondayFirst) {
      $arr = $arr[1..$arr.Length] + $arr[0]
      if (($dow = --$dow) -lt 0) { $dow = 6 }
    }
  }
  process {
    $loc = [DateTimeFormatInfo]::CurrentInfo.MonthNames[$Month - 1] + [Char]32 + $Year
    $loc = "$([Char]32)" * [Math]::Round((20 - $loc.Length) / 2) + $loc
    
    if ($dow -ne 0) { for ($i = 0; $i -lt $dow; $i++) { $arr += "$([Char]32)" * 2} }
    1..$cal.GetDaysInMonth($Year, $Month) | ForEach-Object {
      if ($_.ToString().Length -eq 1) { $arr += "$([Char]32)" + $_ }
      else { $arr += $_ }
    }
  }
  end {
    Write-Host $loc -ForegroundColor Magenta
    for ($i = 0; $i -lt $arr.Length; $i += 6) {
      Write-Host $arr[$i..($i + 6)]
      $i++
    }
    ''
    
    'CultureInfo', 'DateTimeFormatInfo' | ForEach-Object {
      [void]$ta::Remove($_)
    }
  }
}
