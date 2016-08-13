function Get-Reflection {
  <#
    .SYNOPSIS
        Extracts required type from an assembly.
    .PARAMETER Assembly
        Assembly name such as mscorlib, System.Drawing but without extension.
    .PARAMETER TypeName
        Required type to extract from the specified assembly.
    .PARAMETER Function
        If specified returns a method signature instead specified type.
    .PARAMETER Parameters
        Required in special cases (see examples).
    .EXAMPLE
        PS C:\> $par = @{
        >> Assembly = 'UIAutomationClientsideProviders'
        >> TypeName = 'MS.Win32.UnsafeNtiveMethods'
        >> Function = 'SetForegroundWindow'
        >> }
        >>
        PS C:\> Get-Reflection @par
        
        Extracts SetForegroundWindow signture from MS.Win32.UnsafeNativeMethods
        type which stored into UIAutomationClientsideProviders assembly.
    .EXAMPLE
        PS C:\> $par = @{
        >> Assembly = 'mscorlib'
        >> TypeName = 'Microsoft.Win32.Win32Native'
        >> Function = 'GetLongPathName'
        >> Parameters = @([String], [Text.StringBuilder], [Int32])
        >> }
        >>
        PS C:\> Get-Reflection @par
        
        Because there are several signatures of the GetLongPathName function we
        should select that wchich required for target purpose.
    .EXAMPLE
        PS C:\> $LUID = Get-Reflection mscorlib Microsoft.Win32.Win32Native+LUID
        
        Extracts LUID type.
  #>
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Assembly,
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [String]$TypeName,
    
    [Parameter(Position=2)]
    [ValidateNotNullOrEmpty()]
    [String]$Function,
    
    [Parameter(Position=3)]
    [Array]$Parameters
  )
  
  begin {
    function private:Get-Assembly {
      param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Assembly
      )
      
      [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
        $_.ManifestModule.ScopeName.Equals($(
          if ($Assembly -eq 'mscorlib') {
            'CommonLanguageRuntimeLibrary'
          }
          else { "$Assembly.dll" }
        ))
      }
    }
  }
  process {
    if (($asm = Get-Assembly $Assembly) -eq $null) {
      Add-Type -AssemblyName $Assembly -ErrorAction 1
    }
    $type = (Get-Assembly $Assembly).GetType($TypeName)
  }
  end {
    if ($Function) {
      if (($func = $type.GetMethods([Reflection.BindingFlags]60) |
          Where-Object {$_.Name -cmatch $Function}) -is [Array]) {
        if (!$Parameters) {
          Write-Error (New-Object ComponentModel.Win32Exception(0x7F)).Message
          break
        }
        
        $type.GetMethod(
          $Function, [Reflection.BindingFlags]60,
          $null, [Type[]]$Parameters, $null
        )
        break
      }
      $func
    }
    else { $type }
  }
}
