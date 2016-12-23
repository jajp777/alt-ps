#requires -version 5
function Update-Sysinternals {
  <#
    .SYNOPSIS
        Keeps Sysinternals tools in actual state.
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Path $_})]
    [String]$Path #path where tools has been stored
  )
  
  begin {
    $cur, $new = @{}, @{}
    
    $Path = Convert-Path $Path
    (Get-ChildItem "$Path\*.exe").Where{
      $_.VersionInfo.CompanyName -match 'sysinternals'
    }.ForEach{$cur[$_.Name] = $_.VersionInfo.FileVersion}
    
    Write-Verbose "connecting to Sysinternals..."
    if (!(Test-Path "$(($net = (Get-PSDrive).Where{
      $_.DisplayRoot -match 'sysinternals'
    }).Name):")) {
      Write-Verbose "mount Sysinternals drive..."
      net use * https://live.sysinternals.com | Out-Null
      $net = (Get-PSDrive).Where{$_.DisplayRoot -match 'sysinternals'}
    }
  }
  process {
    Write-Verbose "checking for updates..."
    $cur.Keys.ForEach{
      if ($cur[$_] -ne (
        $$ = (Get-Item "$($net.Name):$_").VersionInfo.FileVersion
      )) { $new[$_] = $$ }
    }
  }
  end {
    if (!$new.Count) {
      Write-Host All tools are already updated. -ForegroundColor green
    }
    else {
      $new.Keys.ForEach{
        if(($p = Get-Process $_.Split('.')[0] -ErrorAction 0)) {
          $p.ForEach{Stop-Process $_.Id -Force}
        }
        Write-Verbose "Update: $_"
        Copy-Item "$($net.Name):$_" $Path -Force
      }
      Write-Host Now all tools has actual version. -ForegroundColor cyan
    }
    Write-Verbose "dismount Sysinternals drive..."
    net use "$($net.Name):" /delete | Out-Null
  }
}
