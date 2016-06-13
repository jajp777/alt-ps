function Get-GACPath {
  <#
    .SYNOPSIS
        Locates GAC path.
  #>
  begin {
    $al = New-Object Collections.ArrayList
    
    [Object].Assembly.GetType(
      'Microsoft.Win32.Fusion'
    ).GetMethod(
      'ReadCache'
    ).Invoke($null, @(
      [Collections.ArrayList]$al, $null, [UInt32]3
    ))
    
    Add-Type -AssemblyName ($$ = ($al | Where-Object {
      $_ -cmatch '(?=Microsoft.Build.Tasks)(?!.*(?>resources))'
    })[-1].Split(',')[0])
    
    $asm = [AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.ManifestModule.ScopeName.Equals("$$.dll") }
  }
  process {}
  end {
    ($$ = $asm.GetType(
      'Microsoft.Build.Tasks.GlobalAssemblyCache'
    ).GetMethod(
      'GetGacPath', [Reflection.BindingFlags]40
    ).Invoke($null, @())).Substring(
      0, $$.LastIndexOf('\')
    )
  }
}
