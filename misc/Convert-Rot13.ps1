function Convert-Rot13 {
  <#
    .SYNOPSIS
        Converts rot13 strings into regular strings and vice versa.
    .EXAMPLE
        $key = 'Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist'
        Get-ItemProperty "HKCU:\$key\*\*" | ForEach-Object {
          $_.PSBase.Properties | Where-Object { $_.Name -notlike 'PS*' } |
          Select-Object -ExpandProperty Name | ForEach-Object {
            Convert-Rot13 $_
          }
        }
    .NOTES
        Author: greg zakharov
  #>
  param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [ValidateNotNullOrEmpty()]
    [String[]]$String
  )
  
  begin {
    $rot13 = New-Object 'Collections.Generic.Dictionary[Char, Char]'
    $table = {
      param([Int32[]]$Diapason, [Int32]$Limit)
      
      foreach ($char in $Diapason) {
        $rot13.Add([Char]$char, [Char]$(
          if ($char -le $Limit) { $char + 13 } else { $char - 13 }
        ))
      }
    }
    $table.Invoke(65..90, 77)
    $table.Invoke(97..122, 109)
  }
  process {}
  end {
    foreach ($s in $String) {
      -join ($s.ToCharArray() | ForEach-Object {
        if ($rot13.ContainsKey($_)) { $rot13[$_] } else { $_ }
      })
    }
  }
}
