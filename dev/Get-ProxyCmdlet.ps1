function Get-ProxyCmdlet {
  <#
    .SYNOPSIS
        Returns template of proxy function of the specified cmdlet.
    .EXAMPLE
        PS C:\> Get-ProxyCommand Add-Type
    .NOTES
        Author: greg zakharov
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$Cmdlet
  )
  
  if (!($cmd = Get-Command -CommandType Cmdlet $Cmdlet -ErrorAction 0)) {
    Write-Error "could not find $Cmdlet cmdlet."
    return
  }
  
  [Management.Automation.ProxyCommand]::Create((
    New-Object Management.Automation.CommandMetaData($cmd)
  ))
}
