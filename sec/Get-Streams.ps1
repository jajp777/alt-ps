# region of helper functions
function ConvertFrom-ProcAddress {
  [OutputType([Hashtable])]
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNull()]
    [Object]$ProcAddress,
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNull()]
    [Type[]]$Prototype
  )
  
  begin {
    $arr = New-Object String[]($ProcAddress.Keys.Count)
    $ProcAddress.Keys.CopyTo($arr, 0)
    
    $ret = @{}
  }
  process {}
  end {
    for ($i = 0; $i -lt $arr.Length; $i++) {
      $ret[$arr[$i]] = New-Delegate $ProcAddress[$arr[$i]] $Prototype[$i]
    }
    
    $ret
  }
}

function Get-ProcAddress {
  [OutputType([Collections.Generic.Dictionary[String, IntPtr]])]
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]$Module,
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [String[]]$Function
  )
  
  begin {
    [Object].Assembly.GetType(
      'Microsoft.Win32.Win32Native'
    ).GetMethods(
      [Reflection.BindingFlags]40
    ) | Where-Object {
      $_.Name -cmatch '\AGet(ProcA|ModuleH)'
    } | ForEach-Object {
      Set-Variable $_.Name $_
    }
    
    if (($ptr = $GetModuleHandle.Invoke(
      $null, @($Module)
    )) -eq [IntPtr]::Zero) {
      throw New-Object InvalidOperationException(
        'Could not find specified module.'
      )
    }
  }
  process {}
  end {
    $Function | ForEach-Object {
      $dic = New-Object "Collections.Generic.Dictionary[String, IntPtr]"
    }{
      if (($$ = $GetProcAddress.Invoke(
        $null, @($ptr, [String]$_)
      )) -ne [IntPtr]::Zero) { $dic.Add($_, $$) }
    }{ $dic }
  }
}

function New-Delegate {
  [OutputType([Type])]
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateScript({$_ -ne [IntPtr]::Zero})]
    [IntPtr]$ProcAddress,
    
    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNull()]
    [Type]$Prototype,
    
    [Parameter(Position=2)]
    [ValidateNotNullOrEmpty()]
    [Runtime.InteropServices.CallingConvention]
    $CallingConvention = 'StdCall'
  )
  
  $method = $Prototype.GetMethod('Invoke')
  
  $returntype = $method.ReturnType
  $paramtypes = $method.GetParameters() |
                                 Select-Object -ExpandProperty ParameterType
  
  $holder = New-Object Reflection.Emit.DynamicMethod(
    'Invoke', $returntype, $(
      if (!$paramtypes) { $null } else { $paramtypes }
    ), $Prototype
  )
  $il = $holder.GetILGenerator()
  if ($paramtypes) {
    0..($paramtypes.Length - 1) | ForEach-Object {
      $il.Emit([Reflection.Emit.OpCodes]::Ldarg, $_)
    }
  }
  
  switch ([IntPtr]::Size) {
    4 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I4, $ProcAddress.ToInt32()) }
    8 { $il.Emit([Reflection.Emit.OpCodes]::Ldc_I8, $ProcAddress.ToInt64()) }
  }
  $il.EmitCalli(
    [Reflection.Emit.OpCodes]::Calli, $CallingConvention, $returntype,
    $(if (!$paramtypes) { $null } else { $paramtypes })
  )
  $il.Emit([Reflection.Emit.OpCodes]::Ret)
  
  $holder.CreateDelegate($Prototype)
}
# endregion

function Get-Streams {
  <#
    .SYNOPSIS
        Locates and destroys alternate data streams.
    .NOTES
        Author: greg zakharov
        Requirements: CLR v4
  #>
  [CmdletBinding(DefaultParameterSetName='Path')]
  param(
    [Parameter(Mandatory=$true,
               ParameterSetName='Path',
               Position=0,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$Path,
    
    [Parameter(Mandatory=$true,
               ParameterSetName='LiteralPath',
               Position=0,
               ValueFromPipeline=$false,
               ValueFrompipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [Alias('PSPath')]
    [String]$LiteralPath,
    
    [Parameter()]
    [Switch]$Delete
  )
  
  begin {
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
      $PipelineInput = !$PSBoundParameters.ContainsKey('Path')
    }
    
    function private:Test-Streams {
      param(
        [Parameter(Mandatory=$true)]
        [Object]$Path # IO.FileInfo or IO.DirectoryInfo
      )
      
      $ntdll = Get-ProcAddress ntdll NtQueryInformationFile
      $ntdll = ConvertFrom-ProcAddress $ntdll @(
        [Func[IntPtr, [Byte[]], IntPtr, Int32, Int32, Int32]]
      )
      
      try {
        if (($sfh = [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native'
        ).GetMethod(
          'CreateFile', [Reflection.BindingFlags]40
        ).Invoke($null, @(
          $Path.FullName, 0x80000000, [IO.FileShare]::ReadWrite, $null,
          [IO.FileMode]::Open, 0x02000000, [IntPtr]::Zero
        ))).IsInvalid) {
          throw New-Object InvalidOperationException(
            'Could not open specified file system object.'
          )
        }
        
        $block = 16 * 1024 # potential minimum buffer size
        $isb, $nts = (New-Object Byte[]([IntPtr]::Size)), 0x80000005
        $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal($block)
        
        while ($nts -eq 0x80000005) { # STATUS_BUFFER_OVERFLOW
          if (($nts = $ntdll.NtQueryInformationFile.Invoke(
            $sfh.DangerousGetHandle(), $isb, $ptr, $block, 0x16
          )) -eq 0x80000005) {
            $ptr = [Runtime.InteropServices.Marshal]::ReAllocHGlobal(
              $ptr, [IntPtr]($block *= 2)
            )
          }
          else { break }
        }
        
        $ads = if ($nts -eq 0) {
          $tmp = $ptr
          while ($true) {
            # NextEntryOffset  - offset 0x00
            if (( # INVALID_OFFSET_VALUE = 0x00090178
              $neo = [Runtime.InteropServices.Marshal]::ReadInt32($tmp)
            ) -eq 0x00090178) { break }
            # StreamNameLength - offset 0x04
            $snl = [Runtime.InteropServices.Marshal]::ReadInt32($tmp, 0x04)
            # StreamSize       - offset 0x08
            $ssz = [Runtime.InteropServices.Marshal]::ReadInt64($tmp, 0x08)
            # StreamName       - offset 0x18
            $mov = switch ([IntPtr]::Size) { 4 {$tmp.ToInt32()} 8 {$tmp.ToInt64()} }
            if ([String]::IsNullOrEmpty((
              $itm = [Runtime.InteropServices.Marshal]::PtrToStringUni(
                [IntPtr]($mov + 0x18), $snl / 2
              )
            ))) { break }
            
            if ($itm -ne '::$DATA') {
              New-Object PSObject -Property @{
                Path       = $Path.FullName
                StreamName = $itm
                Length     = $ssz
              }
            }
            if ($neo -eq 0) { break }
            $tmp = [IntPtr]($mov + $neo)
          }
        }
      }
      catch { $_.Message }
      finally {
        if ($ptr) { [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr) }
        if ($sfh) { $sfh.Dispose() }
      }
      
      $ads
    } # Test-Streams
  }
  process {
    $ads = if ($PSCmdlet.ParameterSetName -eq 'Path') {
      switch ($PipelineInput) {
        $true  { Test-Streams $Path }
        $false { Test-Streams (Get-Item $Path) }
      }
    }
    else { Test-Streams (Get-Item -LiteralPath $LiteralPath) }
  }
  end {
    if (!$ads) { return }
    
    $ads | Format-Table -AutoSize
    if ($Delete) {
      $ads | Select-Object Path, StreamName | ForEach-Object {
        $DeleteFile = [Object].Assembly.GetType(
          'Microsoft.Win32.Win32Native'
        ).GetMethod(
          'DeleteFile', [Reflection.BindingFlags]40
        )
      }{ [void]$DeleteFile.Invoke($null, @("$($_.Path)$($_.StreamName)")) }
    }
  }
}

# Export-ModuleMember -Function Get-Streams
