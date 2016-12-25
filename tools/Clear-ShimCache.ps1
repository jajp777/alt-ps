function Clear-ShimCache {
  <#
    .SYNOPSIS
        Flushes the application compatibility cache.
    .DESCRIPTION
        The data of cache is stored in the registry by path
        HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatibility
    .NOTES
        Author: greg zakharov
  #>
  
  if ((New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
  )).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
  )) {
    rundll32 kernel32.dll,BaseFlushAppcompatCache
  }
  else { Write-Warning "You should be an administrator." }
}
