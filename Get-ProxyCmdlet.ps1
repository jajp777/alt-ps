function Get-ProxyCmdlet {
  <#
    .SYNOPSIS
        Returns template of proxy function of the specified cmdlet.
    .EXAMPLE
        PS C:\> Get-ProxyCmdlet Add-Type
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$Cmdlet
  )
  
  begin {}
  process {
    if (!($cmd = Get-Command -CommandType Cmdlet $Cmdlet -ErrorAction 0)) {
      Write-Warning "could not find $Cmdlet cmdlet."
      return
    }
    
    [Management.Automation.ProxyCommand]::Create((
      New-Object Management.Automation.CommandMetaData($cmd)
    ))
  }
  end {}
}
