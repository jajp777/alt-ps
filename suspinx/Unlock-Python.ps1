<#
  .SYNOPSIS
      This code demonstrates a technique to morph Add-Type cmdlet
      on fly.
  .NOTES
      Author: greg zakharov
      Requirements: Python 3 stored into $env:path
#>
function Unlock-Python {
  $unlock, $proxy, $pslang = (@'
        if (![String]::IsNullOrEmpty(
          ${TypeDefinition}
        ) -and ${Language} -eq 'Python') {
          if (!(Get-Command -CommandType Application "$(
            ${Language}
          ).exe" -ErrorAction 0)) {
            Write-Error 'Python interpreter has not been found.'
            break
          }
          
          python -c ${TypeDefinition}
          break
        }
'@ -split "`n"), ([Management.Automation.ProxyCommand]::Create((
    New-Object Management.Automation.CommandMetaData(
      Get-Command -CommandType Cmdlet Add-Type
    )
  )) -split "`n"), ("ValidateSet($(([Enum]::GetValues(
      ($rex = [Microsoft.PowerShell.Commands.Language])
    ) | ForEach-Object { "`'$_`'" }
  ) -join ', '), 'Python')]`n    [System.String")
  # Microsoft.PowerShell.Commands.Language -> String
  $proxy = $proxy -replace $rex, $pslang
  # inject unlock code to proxy
  $line, $code = (
    $proxy | Select-String -Pattern '\$outBuffer\s+\=\s+\$null'
  ).LineNumber, @()
  
  $code += $proxy[0..($line - 2)]
  $code += $unlock
  $code += $proxy[($line - 1)..$proxy.Length]
  # set temporary Add-Type function
  [ScriptBlock]::Create(($code -join "`n"))
}

Set-Content function:Add-Type (Unlock-Python)
Add-Type -Language Python -TypeDefinition @'
print('This code is looking very suspicious...')
'@
