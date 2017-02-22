function Set-VolumeLabel {
  <#
    .SYNOPSIS
        Sets the label of a file system volume.
    .PARAMETER DriveLetter
        The volume's drive letter.
    .PARAMETER VolumeName
        Label for the volume. If this parameter is $null, the
        function deletes any existing label from specified
        volume and does not assign a new label.
    .EXAMPLE
        PS C:\> Set-VolumeLabel E -VolumeName Data
    .EXAMPLE
        PS C:\> Set-VolumeLabel E
        Remove label which has been set with previuos command.
    .NOTES
        Author: greg zakharov
  #>
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidatePattern('[A-Za-z]')]
    [ValidateNotNull()]
    [Char]$DriveLetter,

    [Parameter(Position=1)]
    [AllowNull()]
    [String]$VolumeName = $null
  )

  if (![Object].Assembly.GetType(
    'Microsoft.Win32.Win32Native'
  ).GetMethod(
    'SetVolumeLabel', [Reflection.BindingFlags]40
  ).Invoke($null, @("$($DriveLetter):\", $VolumeName))) {
    Write-Warning (New-Object ComponentModel.Win32Exception(
      [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    )).Message
  }
}
