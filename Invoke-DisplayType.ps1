function Invoke-DisplayType {
  <#
    .SYNOPSIS
        dt command wrapper of the kd.exe tool from Debugging Tools.
    .DESCRIPTION
        The dt command displays information about local variable, global
        variable and data type. This can display information about simple
        data types, as well as structures and unions.
        
        The main goal of this wrapper is to view structures and unions
        without creation crashdump or LiveKd usage.
    .EXAMPLE
        PS C:\> Invoke-DisplayType ole32 system*
        
        On Windows 7 this returns a list of data types which started
        with 'SYSTEM' word.
    .EXAMPLE
        PS C:\> Invoke-DisplayType ole32 system_timeofday_information
        
        On Windows 7 this returns data about SYSTEM_TIMEOFDAY_INFORMATION
        structure.
    .EXAMPLE
        PS C:\> Invoke-DisplayType ole32 system_timeofday_information /r
        
        Same that above, but also dumps the subtype fields.
    .EXAMPLE
        PS C:\> Invoke-DisplayType urlmon system_timeofday_information /r
        
        Same that above but for Windows XP.
    .NOTES
        Dependencies: Debugging Tools.
        Requirements: be sure that _NT_SYMBOL_PATH is defined and
                      debugging tools directory stored into PATH.
        Macros
          Actually, you can do a simple macro for this purpose. For more
          details see: https://github.com/gregzakh/sh-monsters#useful-macros
  #>
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Module,
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [String]$DataType,
    
    [Parameter(Position=2)]
    [String]$Arguments = $null
  )
  
  begin {
    if (!$Module.EndsWith('.dll')) {
      $BaseName = $Module
      $Module += '.dll'
    }
    else {
      $BaseName = $Module.Substring(0, $Module.LastIndexOf('.'))
    }
    $Module = "$([Environment]::SystemDirectory)\$Module"
    
    if (!(Test-Path $Module)) {
      throw "Module $Module has not been found."
    }
  }
  process {
    kd -z $Module -c "dt $BaseName!_$DataType $Arguments;q" -r -snc|
    Select-String -Pattern "$(if ($DataType.EndsWith('*')) {
      "\A\s+$BaseName!_"
    } else {'\+|='} )"
  }
  end {}
}
