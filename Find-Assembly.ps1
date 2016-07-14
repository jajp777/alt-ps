function Find-Assembly {
  <#
    .SYNOPSIS
        Locates an assembly in global assembly cache.
    .DESCRIPTION
        If no assembly has been specified then the
        functions returns all assemblies deployed
        in global assembly cache.
  #>
  param(
    [Parameter(ValueFromPipeline=$true)]
    [String]$AssemblyName
  )
  
  $al = New-Object Collections.ArrayList
  [Object].Assembly.GetType(
    'Microsoft.Win32.Fusion'
  ).GetMethod(
    'ReadCache'
  ).Invoke($null, @(
    [Collections.ArrayList]$al,
    $(if ([String]::IsNullOrEmpty($AssemblyName)) {
      $null         #all assemblies will be printed
    }
    else {
      $AssemblyName #only specified assembly
    }),
    [UInt32]2
  ))
  $al
}
