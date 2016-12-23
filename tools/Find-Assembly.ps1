function Find-Assembly {
  <#
    .SYNOPSIS
        Locates an assembly in global assembly cache.
    .DESCRIPTION
        If no assembly name has been specified then
        the function returns all assemblies deployed
        in global assembly cache.
    .NOTES
        Author: greg zakharov
  #>
  param(
    [Parameter(ValueFromPipeline=$true)]
    [String]$AssemblyName
  )
  
  $al = New-Object Collections.ArrayList
  [Object].Assembly.GetType(
    'Microsoft.Win32.Fusion'
  ).GetMethod('ReadCache').Invoke($null, @(
    [Collections.ArrayList]$al,
    $(if ([String]::IsNullOrEmpty(
      $AssemblyName
    )) { $null } else { $AssemblyName }),
    [UInt32]2
  ))
  $al
}
