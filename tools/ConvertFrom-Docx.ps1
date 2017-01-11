function ConvertFrom-Docx {
  <#
    .SYNOPSIS
        Converts Word document (.docx) to a text plain.
    .DESCRIPTION
        This function is provided AS IS since it does not provide specific
        checks such as file format, compression and etc.
    .EXAMPLE
        PS C:\> Get-ZipContent \doc\pecoff_v83.docx
        
        DateTime           Attributes    Size Compressed Name
        --------           ----------    ---- ---------- ----
        01.01.1980 0:00:00          0    2751        497 [Content_Types].xml
        01.01.1980 0:00:00          0     590        243 _rels/.rels
        01.01.1980 0:00:00          0    4755        756 word/_rels/document.xml.rels
        01.01.1980 0:00:00          0 1329567     123898 word/document.xml
        01.01.1980 0:00:00          0    1755        610 word/header2.xml
        01.01.1980 0:00:00          0    1231        391 word/header1.xml
        01.01.1980 0:00:00          0    1226        417 word/footer3.xml
        01.01.1980 0:00:00          0    1896        665 word/footer2.xml
        01.01.1980 0:00:00          0    1430        426 word/footer1.xml
        01.01.1980 0:00:00          0    2469        915 word/header3.xml
        01.01.1980 0:00:00          0    1734        467 word/endnotes.xml
        01.01.1980 0:00:00          0    1740        466 word/footnotes.xml
        01.01.1980 0:00:00          0     289        188 word/_rels/header3.xml.rels
        01.01.1980 0:00:00          0    6992       1686 word/theme/theme1.xml
        01.01.1980 0:00:00          0    2616       2616 word/media/image3.png
        01.01.1980 0:00:00          0   25088      14337 word/embeddings/Microsoft_Visio_2003-2010_Drawing22.vsd
        01.01.1980 0:00:00          0   52736      26744 word/embeddings/Microsoft_Visio_2003-2010_Drawing11.vsd
        01.01.1980 0:00:00          0   24232       6385 word/media/image1.emf
        01.01.1980 0:00:00          0    5364       1841 word/media/image2.emf
        01.01.1980 0:00:00          0   27660       6148 word/settings.xml
        01.01.1980 0:00:00          0    3653        844 word/fontTable.xml
        01.01.1980 0:00:00          0    1593        409 word/webSettings.xml
        01.01.1980 0:00:00          0   58024       7397 word/styles.xml
        01.01.1980 0:00:00          0   58777       7534 word/stylesWithEffects.xml
        01.01.1980 0:00:00          0     978        481 docProps/app.xml
        01.01.1980 0:00:00          0     621        325 docProps/core.xml
        01.01.1980 0:00:00          0   87512       6025 word/numbering.xml
        
        #required data is kept in "word/document.xml" file
        PS C:\> ConvertFrom-Docx \doc\pecoff_v83.docx
        ...
    .NOTES
        Author: greg zakharov
  #>
  param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Path $_})]
    [String]$Path
  )
  
  begin {}
  process {
    try {
      $fs = [IO.File]::OpenRead((Convert-Path $Path))
      $br = New-Object IO.BinaryReader($fs)
      
      while ($true) { # just walk around of local headers
        if ($br.ReadUInt32() -ne 0x4034b50) { break }
        
        $fs.Position += 14
        # compressed and uncompressed size
        $csz, $usz = $br.ReadUInt32(), $br.ReadUInt32()
        # name length and extra field size
        $nsz, $xsz = $br.ReadUInt16(), $br.ReadUInt16()
        
        if ((-join $br.ReadChars($nsz)) -eq 'word/document.xml') {
          $fs.Position += $xsz # skip extra field
          
          try {
            $ds = New-Object IO.Compression.DeflateStream($fs, 'Decompress')
            
            $buf = New-Object Byte[]($usz)
            [void]$ds.Read($buf, 0, $buf.Length)
            $xml = [xml][Text.Encoding]::UTF8.GetString($buf)
          }
          finally {
            if ($ds) { $ds.Dispose() }
          }
          
          break # that's done!
        }
        # next entry (compressed size plus extra field size)
        $fs.Position += $csz + $xsz
      }
    }
    finally {
      if ($br) { $br.Close() }
      if ($fs) { $fs.Dispose() }
    }
  }
  end {
    if ($xml) { $xml.document.InnerText }
  }
}
