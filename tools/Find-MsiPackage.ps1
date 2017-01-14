function Find-MsiPackage {
  <#
    .SYNOPSIS
        Gets packages deployed with msiexec service.
    .EXAMPLE
        PS C:\> Find-MsiPackage
        Prints names of all packages deployed with msiexec.
    .EXAMPLE
        PS C:\> Find-MsiPackage microsoft
        Searches all packages which contains "microsoft"
        word in their names.
    .NOTES
        Author: greg zakharov
  #>
  param(
    [Parameter(ValueFromPipeline=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$Package
  )

  begin {
    $msi = New-Object -ComObject WindowsInstaller.Installer
  }
  process {
    $packages = $(($mt = $msi.GetType()).InvokeMember(
      'Products', 'GetProperty', $null, $msi, $null
    ) | ForEach-Object {
      $names = $mt.InvokeMember(
        'ProductInfo', 'GetProperty', $null, $msi, @(
          [String]$_, 'ProductName'
        )
      )

      foreach ($name in $names) {
        New-Object PSObject -Property @{
          Name = $name
          Guid = [String]$_
        }
      }
    }) | Where-Object { $_.Name -match $Package }
  }
  end {
    $packages | Format-Table -AutoSize
  }
}
