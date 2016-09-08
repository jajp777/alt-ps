function Test-MyGeo {
  <#
    .SYNOPSIS
        Grabs approximate location of a user which is
        presented by the Yandex.Internet service.
    .NOTES
        Dependencies: HtmlAgilityPack.dll
        See https://www.nuget.org/packages/HtmlAgilityPack/
        
        Because from time to time Yandex changes its own
        API this function can might not work in future.
  #>
  begin {
    # modify this path for correct work
    Add-Type -Path F:\Assemblies\HtmlAgilityPack.dll
  }
  process {
    try {
      if ([String]::IsNullOrEmpty(($htm = (
        $wc = New-Object Net.WebClient
      ).DownloadString(
        'https://www.yandex.com/internet'
      )))) {
        throw 'Unable get approximate location.'
      }
    }
    catch { $_.Exception }
    finally {
      if ($wc) { $wc.Dispose() }
    }
  }
  end {
    if (!$htm) { return }
    
    (
      $hap = New-Object HtmlAgilityPack.HtmlDocument
    ).LoadHtml($htm)
    $hap.DocumentNode.SelectNodes(
      "//span"
    ) | Where-Object {
      $_.Attributes['class'].Value -match `
      '(info__value(\s+)?){2}_type_(ip(\d)?|pinpoint)'
    } | ForEach-Object { $geo = @{} }{
      $geo[$_.Attributes['class'].Value.Split(
        '_'
      )[-1]] = $_.InnerText
    }{
      New-Object PSObject -Property $geo | Format-List
    }
  }
}
