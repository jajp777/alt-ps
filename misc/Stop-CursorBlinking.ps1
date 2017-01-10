function Stop-CursorBlinking {
  <#
    .SYNOPSIS
        [Dis|En]ables blinking of the console cursor.
    .NOTES
        Author: greg zakharov
  #>
  param([Switch]$Cancel)

  begin {
    ($asm = [Object].Assembly.GetType(
      'Microsoft.Win32.Win32Native'
    )).GetMethods([Reflection.BindingFlags]40) |
    Where-Object {
      $_.Name -cmatch '\A(Get|Set)(Std|ConsoleCursorI)'
    } | ForEach-Object {
      Set-Variable $_.Name $_
    }

    $STD_OUTPUT_HANDLE = $asm.GetField(
      'STD_OUTPUT_HANDLE', [Reflection.BindingFlags]40
    ).GetValue($null)

    $cci = [Activator]::CreateInstance(
      [Object].Assembly.GetType(
        'Microsoft.Win32.Win32Native+CONSOLE_CURSOR_INFO'
      )
    )
  }
  process {
    $out = $GetStdHandle.Invoke($null, @($STD_OUTPUT_HANDLE))

    if (!$GetConsoleCursorInfo.Invoke(
      $null, ($par = [Object[]]@($out, $cci))
    )) {
      $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
      throw (New-Object ComponentModel.Win32Exception($err)).Message
    }

    if (($sz = $par[1].GetType().GetField(
      'dwSize', [Reflection.BindingFlags]36
    ).GetValue($par[1])) -lt 1 -and $sz -gt 100) {
      throw New-Object InvalidOperationException(
        'Cursor data has invalid size parameter.'
      )
    }

    $set = if ($Cancel) { $true } else { $false }
    $par[1].GetType().GetField(
      'bVisible', [Reflection.BindingFlags]36
    ).SetValue($par[1], $set)
  }
  end {
    if (!$SetConsoleCursorInfo.Invoke($null, @($out, $par[1]))) {
      $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
      throw (New-Object ComponentModel.Win32Exception($err)).Message
    }
  }
}
