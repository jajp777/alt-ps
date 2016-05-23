#requires -version 2
<#
  .NOTES
      This script is useful for PowerShell v2, on higher versions
      it's better to use #requires operator with RunAsAdministrator
      parameter: it invokes IsAdministrator method stored into
      System.Management.Automation.dll assembly.
      
      [PSObject].Assembly.GetType(
        'System.Management.Automation.Utils'
      ).GetMethod(
        'IsAdministrator', [Reflection.BindingFlags]40
      ).Invoke($null, @())
      
      So you shouldn't bother to write additional code such as
      present below, just place
      
      #requires -RunAsAdministrator
      
      at the start of script and it's done.
#>
@{
  ($$ = [Security.Principal.WindowsIdentity]::GetCurrent()).Name =
    ((New-Object Security.Principal.WindowsPrincipal($$)).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator
    )
  )
}
