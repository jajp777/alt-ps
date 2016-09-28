function Get-DisplayDevices {
  <#
    .SYNOPSIS
        Gets information about the display devices in the current
        session.
    .NOTES
        typedef struct _DISPLAY_DEVICE { // A |      W
          DWORD cb;                 // +0x000 | +0x000
          TCHAR DeviceName[32];     // +0x004 | +0x004
          THCAR DeviceString[128];  // +0x024 | +0x044
          DWORD StateFlags;         // +0x0a4 | +0x144
          TCHAR DeviceID[128;       // +0x0a8 | +0x148
          TCHAR DeviceKey[128];     // +0x128 | +0x248
        } DISPLAY_DEVICE, *PDISPLAY_DEVICE;
        
        sizeof(DISPLAY_DEVICEA) = 424;
        sizeof(DISPLAY_DEVICEW) = 840;
  #>
  begin {
    function private:New-Delegate {
      param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Module,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Function,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Delegate
      )
      
      begin {
        [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native'
        ).GetMethods([Reflection.BindingFlags]40) |
        Where-Object {
          $_.Name -cmatch '\AGet(ProcA|ModuleH)'
        } | ForEach-Object {
          Set-Variable $_.Name $_
        }
        
        if (($ptr = $GetProcAddress.Invoke($null, @(
          $GetModuleHandle.Invoke($null, @($Module)), $Function
        ))) -eq [IntPtr]::Zero) {
          throw New-Object InvalidOperationException(
            'Could not find specified signature.'
          )
        }
      }
      process { $proto = Invoke-Expression $Delegate }
      end {
        $method = $proto.GetMethod('Invoke')
        
        $returntype = $method.ReturnType
        $paramtypes = $method.GetParameters() |
                    Select-Object -ExpandProperty ParameterType
        
        $holder = New-Object Reflection.Emit.DynamicMethod(
          'Invoke', $returntype, $paramtypes, $proto
        )
        $il = $holder.GetILGenerator()
        0..($paramtypes.Length - 1) | ForEach-Object {
          $il.Emit([Reflection.Emit.OpCodes]::Ldarg, $_)
        }
        
        switch ([IntPtr]::Size) {
          4 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, $ptr.ToInt32()) }
          8 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8, $ptr.ToInt64()) }
        }
        $il.EmitCalli(
          [Reflection.Emit.OpCodes]::Calli,
          [Runtime.InteropServices.CallingConvention]::StdCall,
          $returntype, $paramtypes
        )
        $il.Emit([Reflection.Emit.OpCodes]::Ret)
        
        $holder.CreateDelegate($proto)
      }
    }
    
    $EnumDisplayDevices = New-Delegate user32 EnumDisplayDevicesW `
                      '[Func[[Byte[]], UInt32, [Byte[]], UInt32, Boolean]]'
    $STATE_FLAGS = @{
      AttachedToDesktop  = 0x00000001
      MultiDriver        = 0x00000002
      PrimaryDevice      = 0x00000004
      MirroringDrive     = 0x00000008
      VgaCompatible      = 0x00000010
      Removable          = 0x00000020
      UnsfaeModesOn      = 0x00080000
      DeviceTSCompatible = 0x00200000
      Disconnect         = 0x02000000
      Remote             = 0x04000000
      ModeSpruned        = 0x08000000
    }
  }
  process {
    $ddw = New-Object Byte[] 840 # DISPLAY_DEVICEW
    # set size of the DISPLAY_DEVICEW structure
    $ddw[0] = [Byte]0x48
    $ddw[1] = [Byte]0x3
    
    $i = 0
    while ($EnumDisplayDevices.Invoke($null, $i, $ddw, 0)) {
      New-Object PSObject -Property @{
        DeviceName = [Text.Encoding]::Unicode.GetString($ddw[4..35])
        DeviceString = [Text.Encoding]::Unicode.GetString($ddw[68..195])
        StateFlags = $(
          $f = [BitConverter]::ToUInt32($ddw[324..327], 0)
          foreach ($key in $STATE_FLAGS.Keys) {
            if (($f -band $STATE_FLAGS[$key]) -eq $STATE_FLAGS[$key]) { $key }
          }
        )
        DeviceId = [Text.Encoding]::Unicode.GetString($ddw[328..455])
        DeviceKey = [Text.Encoding]::Unicode.GetString(
          $ddw[584..839]
        ).Trim("`0") -replace '\\registry\\machine', 'HKLM'
      } | Select-Object DeviceName, DeviceString, StateFlags, DeviceID, DeviceKey
      $i++
    }
  }
  end {}
}
