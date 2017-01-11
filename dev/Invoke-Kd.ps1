function Invoke-Kd {
  <#
    .SYNOPSIS
        Wrappers of some kd.exe commands.
    .DESCRIPTION
        More information can be found in official documentation
        distrubuted with debugging tools.
    .EXAMPLE
        PS C:\> Invoke-Kd ole32 @{Command='dt';Type='PEB';Recurse=$true}
        This command shows PEB structure in recursive presentation.
    .EXAMPLE
        PS C:\> Invoke-Kd ole32 @{Command='sizeof';Type='PEB'}
        Returns the size of PEB structure for cuurent OS version.
    .EXAMPLE
        PS C:\> Invoke-Kd shlwapi @{Command='x';Type='*shell*'}
        Displays the symbols in all contexts that match the specified
        pattern.
    .NOTES
        Author: greg zakharov
        Dependencies: Debugging Tools
        Requirements: be sure that _NT_SYMBOL_PATH defined and Debugging
                      Tools directory stored into PATH variable.
        Remarks
        --------
        There are a few of different techniques to verify that Debugging
        Tools has been installed.

        # Registry
        $f = Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\Installer\Folders
        $f.PSObject.Properties | Where-Object {
          $_.Name -match 'debugging tools'
        } | ForEach-Object {
          if (Test-Path "$($_.Name)kd.exe") { $_.Name; break }
        }

        # Shortcut
        $f = (Get-ChildItem $env:allusersprofile -Include *.lnk -Recurse |
        Where-Object { $_.Name -match 'windbg' }).FullName
        (New-Object -ComObject WScript.Shell
        ).CreateShortcut($f).WorkingDirectory

        # $env:PATH
        Split-Path (Get-Command -CommandType Application kd).Path

        and etc.
  #>
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Module,

    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNull()]
    [Hashtable]$Parameters
  )

  begin {
    if ($Module -notmatch '\.dll\Z') { $Module += '.dll' }
    $Module = "$([Environment]::SystemDirectory)\$Module"

    if (!(Test-Path $Module)) {
      throw New-Object IO.IOException(
        'Could not find specified module.'
      )
    }
  }
  process {}
  end {
    $BaseName = ([IO.FileInfo]$Module).BaseName
    switch ($Parameters.Command) {
      'dt'     {
        if ([String]::IsNullOrEmpty($Parameters.Type)) {
          $Parameters.Type = '*'
        }

        if ($Parameters.Type -eq '*' -and $Parameters.Recurse) {
          $Parameters.Remove('Recurse')
        }

        kd -z $Module -c "dt $BaseName!_$($Parameters.Type) $(
          if ($Parameters.Recurse) {'/r'}
        );q" -r -snc | Select-String -Pattern '\A\s+'
      }
      'sizeof' {
        if ([String]::IsNullOrEmpty($Parameters.Type)) {
          throw New-Object InvalidOperationException(
            'A type name is strongly required.'
          )
        }

        kd -z $Module -c "?? sizeof(
          $BaseName!_$($Parameters.Type)
        );? @`$exp;q" -r -scn | Select-String -Pattern 'eval'
      }
      'x'      {
        if ([String]::IsNullOrEmpty($Parameters.Type)) {
          $Parameters.Type = '*'
        }

        kd -z $Module -c "x $BaseName!_$($Parameters.Type);q" |
        Select-String -Pattern "[0-9a-fA-F]+\s+$BaseName"
      }
    }
  }
}
