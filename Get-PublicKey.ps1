function Get-PublicKey {
  <#
    .SYNOPSIS
        Extracts the public key of VirusTotal service
        from Sysinternals sigcheck.exe tool.
    .DESCRIPTION
        Actually, it is strongly recommended get your
        personal key. It's really free and lets you
        upload and scan files, submit and scan URLs,
        access finished scan reports and make
        automatic commenrs on URLs and files without
        the need of using HTML website interface.
    .EXAMPLE
        function Add-Comment {
          param(
            [Parameter(Mandatory=$true, Position=0)]
            [ValidateNotNullOrEmpty()]
            [String]$Hash,
            
            [Parameter(Mandatory=$true, Position=1)]
            [ValidateNotNullOrEmpty()]
            [String]$Comment
          )
          
          begin {
            if (!($key = Get-PublicKey)) {
              Write-Error 'unable get public key.'
              return
            }
            
            $url = "http://www.virustotal.com/vtapi/v2/comments/put?$(@(
              "comment=$([Uri]::EscapeDataString($Comment))"
              "apikey=$key"
              "resource=$Hash"
            ) -join '&')"
          }
          process {}
          end {
            $wr = [Net.WebRequest]::Create($url)
            $wr.Method = 'POST'
            $wr.ContentLength = 0
            $wr.GetResponse()
          }
        }
        
        Add-Comment 89b5a61352989fec2d6e32072c10fd28 'Comment text'
  #>
  begin {
    try {
      $wc = New-Object Net.WebClient
      $bytes = $wc.DownloadData(
        'https://live.sysinternals.com/sigcheck.exe'
      )
    }
    catch { $_.Exception }
    finally {
      if ($wc) { $wc.Dispose() }
    }
  }
  process {}
  end {
    if (!$bytes) { return }
    
    (([Regex]'[\x20-\x7E]{64}').Matches(
      [Text.Encoding]::UTF7.GetString($bytes)
    ) | Where-Object {
      $_.Value -match '\A([a-z]|\d)+\Z'
    }).Value
  }
}
