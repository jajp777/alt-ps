function Get-DllExports {
  <#
    .SYNOPSIS
        Locates exported functions inside specified system module (DLL).
    .EXAMPLE
        PS C:\> Get-DllExports ntdll
        Finds functions names with ordinals into ntdll.dll module.
    .NOTES
        Author: greg zakharov
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$Module
  )
  
  begin {
    if ($Module -notmatch '\.dll\Z') { $Module += '.dll' }
    if (!(Test-Path ($Module =
      "$([Environment]::SystemDirectory)\$Module"
    ))) {
      Write-Error 'could not find specified module.'
      break
    }
    # getting sections and export table data
    function private:Test-Binary($Path) {
      try {
        $fs = [IO.File]::OpenRead($Path)
        $br = New-Object IO.BinaryReader($fs)
        
        $e_magic = $br.ReadUInt16() # MZ
        $fs.Position = 0x3C
        $fs.Position = $br.ReadUInt16()
        $pe_sign = $br.ReadUInt32() # PE\0\0
        
        if ($e_magic -ne 23117 -and $pe_sign -ne 17744) {
          throw New-Object Exception('Unknown file format.')
        }
        
        # number of sections
        $fs.Position += 0x02
        $pe_sec = $br.ReadUInt16()
        # size of optional header
        $fs.Position += 0x0C
        $pe_ioh = $br.ReadUInt16()
        # PE or PE+
        $fs.Position += 0x02
        $buf = $fs.Position # begin of optional header
        switch ($script:format = $br.ReadUInt16()) {
          0x10B { $fs.Position += 0x1A; $img_base = $br.ReadUInt32() }
          0x20B { $fs.Position += 0x16; $img_base = $br.ReadUInt64() }
          default { throw New-Object Exception('Unknown machine type.') }
        }
        # check that export directory exists
        $fs.Position = $buf + ($pe_ioh - 0x80) # 0x80 - size of directories
        $addr, $size = $br.ReadUInt32(), $br.ReadUInt32()
        
        if ($addr -eq 0 -and $size -eq 0) {
          throw New-Object Exception('Does not contain exports.')
        }
        # IMAGE_SECTION_HEADER[]
        $fs.Position += 0x78 # 0x80 - sizeof(export directory)
        $script:Sections = 0..($pe_sec - 1) | ForEach-Object {
          $sec_name = -join [Char[]]$br.ReadBytes(8)
          $vrt_size = $br.ReadUInt32()
          $vrt_addr = $br.ReadUInt32()
          $fs.Position += 0x04
          $ptr_data = $br.ReadUInt32()
          
          if (($mov = $addr - $vrt_addr) -ge 0 -and $mov -lt $vrt_size) {
            $ptr_strc = $ptr_data + $mov
          }
          
          New-Object PSObject -Property @{
            Name             = $sec_name
            VirtualAddress   = $vrt_addr
            VirtualSize      = $vrt_size
            PointerToRawData = $ptr_data
          }
          $fs.Position += 0x10 # move to the next entry
        }
        # IMAGE_EXPORT_DIRECTORY
        $fs.Position = $ptr_strc
        $IMAGE_EXPORT_DIRECTORY = New-Object PSObject -Property @{
          Characteristics       = $br.ReadUInt32()
          TimeDateStamp         = ( # unix time format
            [DateTime]'1/1/1970').AddSeconds($br.ReadUInt32()).ToLocalTime()
          Version               = '{0}.{1}' -f $br.ReadUInt16(), $br.ReadUInt16()
          Name                  = $br.ReadUInt32()
          Base                  = $br.ReadUInt32()
          NumberOfFunctions     = $br.ReadUInt32()
          NumberOfNames         = $br.ReadUInt32()
          AddressOfFunctions    = $br.ReadUInt32()
          AddressOfNames        = $br.ReadUInt32()
          AddressOfNameOrdinals = $br.ReadUInt32()
        }
      }
      catch { Write-Verbose $_ }
      finally {
        if ($br) { $br.Dispose() }
        if ($fs) { $fs.Dispose() }
      }
      
      $IMAGE_EXPORT_DIRECTORY
    }
    # image rva to va
    function private:Convert-ImageRvaToVa($Rva) {
      foreach ($sec in $script:Sections) {
        if (($rva -ge $sec.VirtualAddress) -and (
          $rva -lt ($sec.VirtualAddress + $sec.VirtualSize)
        )) {
          return [IntPtr]($rva - (
            $sec.VirtualAddress - $sec.PointerToRawData
          ))
        }
      }
    }
    # accelerate Marshal type
    if (($ta = [PSObject].Assembly.GetType(
      'System.Management.Automation.TypeAccelerators'
    ))::Get.Keys -notcontains 'Marshal') {
      $ta::Add('Marshal', [Runtime.InteropServices.Marshal])
    }
  }
  process {
    if (($ied = Test-Binary $Module).Name -eq 0) {
      Write-Error 'corrupted data.'
      return
    }
    
    $buf, $fun, $ord = [IO.File]::ReadAllBytes($Module), (
      Convert-ImageRvaToVa $ied.AddressOfNames
    ), (Convert-ImageRvaToVa $ied.AddressOfNameOrdinals)
    
    try {
      $img = [Marshal]::AllocHGlobal($buf.Length)
      [Marshal]::Copy($buf, 0, $img, $buf.Length)
      
      $exports = foreach ($i in 0..($ied.NumberOfNames - 1)) {
        New-Object PSObject -Property @{
          Name = [Marshal]::PtrToStringAnsi($img.ToInt64() + (
            Convert-ImageRvaToVa $([Marshal]::ReadInt32(
              $img.ToInt64() + $fun + ($i * 4)
          ))))
          Ordinal = [Marshal]::ReadInt16(
            $img.ToInt64() + $ord + ($i * 2)) + $ied.Base
        }
      }
    }
    catch { Write-Verbose $_ }
    finally {
      if ($img) { [Marshal]::FreeHGlobal($img) }
    }
  }
  end {
    $exports | Format-Table -AutoSize
    if ($ta) { [void]$ta::Remove('Marshal') }
  }
}
