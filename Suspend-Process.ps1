function Suspend-Process {
  <#
    .SYNOPSIS
        Suspends or resumes a process.
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateScript({($script:proc = Get-Process -Id $_ -ea 0) -ne 0})]
    [Int32]$Id
  )
  
  begin {
    function private:New-DllImport {
      param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]$Function,
        
        [Parameter(Mandatory=$true, Position=2)]
        [Type]$ReturnType,
        
        [Parameter(Position=3)]
        [Type[]]$Parameters,
        
        [Parameter()]
        [Switch]$SetLastError,
        
        [Parameter()]
        [Runtime.InteropServices.CharSet]$CharSet = 'Auto',
        
        [Parameter()]
        [Runtime.InteropServices.CallingConvention]$CallingConvention = 'WinApi',
        
        [Parameter()]
        [String]$EntryPoint
      )
      
      begin {
        $mod = if (!($m = $ExecutionContext.SessionState.PSVariable.Get(
            'PowerShellDllImport'
        ))) {
          $mb = ([AppDomain]::CurrentDomain.DefineDynamicAssembly(
            (New-Object reflection.AssemblyName('PowerShellDllImport')), 'Run'
          )).DefineDynamicModule('PowerShellDllImport', $false)
          
          Set-Variable PowerShellDllImport -Value $mb -Option Constant `
                                           -Scope Global -Visibility Private
          $mb # first execution
        }
        else { $m.Value }
      }
      process {}
      end {
        try { $pin = $mod.GetType("${Function}Sig") }
        catch {}
        finally {
          if (!$pin) {
            $pin = $mod.DefineType("${Function}Sig", 'Public, BeforeFieldInit')
            $fun = $pin.DefineMethod(
              $Function, 'Public, Static, PinvokeImpl', $ReturnType, $Parameters
            )
            
            $Parameters | ForEach-Object { $i = 1 }{
              if ($_.IsByRef) { [void]$fun.DefineParameter($i, 'Out', $null) }
              $i++
            }
            
            ($dllimport = [Runtime.InteropServices.DllImportAttribute]).GetFields() |
            Where-Object { $_.Name -cmatch '\A(C|En|S)' } | ForEach-Object {
              Set-Variable "_$($_.Name)" $_
            }
            $ErrorValue = if ($SetLastError) { $true } else { $false }
            $EntryPoint = if ($EntryPoint) { $EntryPoint } else { $Function }
            
            $atr = New-Object Reflection.Emit.CustomAttributeBuilder(
              $dllimport.GetConstructor([String]), $Module, [Reflection.PropertyInfo[]]@(),
              [Object[]]@(), [Reflection.FieldInfo[]]@(
                $_SetLastError, $_CallingConvention, $_CharSet, $_EntryPoint
              ), [Object[]]@(
                $ErrorValue, [Runtime.InteropServices.CallingConvention]$CallingConvention,
                [Runtime.InteropServices.CharSet]$CharSet, $EntryPoint
              )
            )
            $fun.SetCustomAttribute($atr)
            
            $pin = $pin.CreateType()
          }
          $pin
        }
      }
    }
    
    $ntdll_1 = New-DllImport ntdll NtSuspendProcess ([Int32]) @([IntPtr])
    $ntdll_2 = New-DllImport ntdll NtResumeProcess  ([Int32]) @([IntPtr])
  }
  process {
    if (!$proc.Handle) {
      throw (New-Object ComponentModel.Win32Exception(5)).Message
    }
    
    if (!$(if ($proc.Responding) {
      $ntdll_1::NtSuspendProcess($proc.Handle)
    }
    else { $ntdll_2::NtResumeProcess($proc.Handle) })) {
      $true
    } else { $false }
  }
  end {}
}
