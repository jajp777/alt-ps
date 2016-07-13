function Convert-Rot13 {
  <#
    .SYNOPSIS
        Converts rot13 strings into regular strings and vice versa.
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
      
      $Diapason | ForEach-Object {
        $rot13.Add([Char]$_, [Char]$(
          if ($_ -le $Limit) {$_ + 13} else {$_ - 13}
        ))
      }
    }
    $table.Invoke(65..90, 77)
    $table.Invoke(97..122, 109)
  }
  process {
    $String | ForEach-Object {
      -join ($_.ToCharArray() | ForEach-Object {
        if ($rot13.ContainsKey($_)) {$rot13[$_]} else {$_}
      })
    }
  }
  end {}
}
