function Get-GACPath {
  <#
    .SYNOPSIS
        Locates GAC path.
    .NOTES
        Author: greg zakharov
  #>
  begin {
    $al = New-Object Collections.ArrayList
    
    [Object].Assembly.GetType(
      'Microsoft.Win32.Fusion'
    ).GetMethod(
      'ReadCache'
    ).Invoke($null, @(
      [Collections.ArrayList]$al, $null, [UInt32]2
    ))
    
    Add-Type -AssemblyName ($asm = ($al | Where-Object {
      $_ -cmatch '(?=Microsoft.Build.Tasks)(?!.*(?>resources))'
    })[-1])
    
    $asm = [AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.ManifestModule.ScopeName.Equals(
      "$($asm.Split(',')[0]).dll"
    ) }
  }
  process {}
  end {
    Split-Path ($asm.GetType(
      'Microsoft.Build.Tasks.GlobalAssemblyCache'
    ).GetMethod(
      'GetGacPath', [Reflection.BindingFlags]40
    ).Invoke($null, @()))
  }
}
