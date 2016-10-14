#requires -Version 5 -RunAsAdministrator
function Invoke-WMINavigator {
  Add-Type -AssemblyName System.Windows.Forms
  
  $fnt1 = New-Object Drawing.Font('Tahoma', 9, [Drawing.FontStyle]::Bold)
  $fnt2 = New-Object Drawing.Font('Tahoma', 8, [Drawing.FontStyle]::Bold)
  
  $img1 = 'iVBORw0KGgoAAAANSUhEUgAAAA0AAAANCAIAAAD9iXMrAAAAAXNSR0IArs4' +
          'c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAACZSU' +
          'RBVChTjZGBDYQgDEVB1nAtjh0IC+CkBAQmIdyXXuqJyZ0vUX6bF2yj7L2LB' +
          'yx07Pv+GlBJudZKJTi8Usq2bQjOudEU1lq8vfesfu4j1nWdAnPx7kgpKRxe' +
          'a42KCUjnxSklrbUxJueM3RnuY3qUAg8MtECMcTg9hPAtgct8SqkpMKe3LL9' +
          '2+rPvCX2eR0TG+tNw4Nn/FeINerd2h++kyh0AAAAASUVORK5CYII='
  $img2 = 'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAAXNSR0IArs4' +
          'c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAJgSU' +
          'RBVDhPY/iPBD6/v7tthuKnt7f+//8HFcIACA0g1dOlvt+IXNHF//HtTVx6G' +
          'IGYgYHhy4d7B5ZaWVlZ/Pr1Cyhy4MBB77QLfEJqQCk0ANIAVL1vsYWBgd6P' +
          'Hz++fv0KFBUVFT18+EhkxTeIImTABFS9e4Gpqqryq1evnj179vHjR6C2c5e' +
          'f+qRfBEo//vxTsH4NkAQ5AwyY9i7zkJAQf/fuHUQ10MLXH5gcwzfwCqoA1Q' +
          'VuuJGUHKLdtenBx+8QDYxAvwJtkJAQe/36NRsb26//gmeeBvxnYALKrRB3d' +
          'XW1AzK4uBjmzl33viEIyGbiEVByTTj97NkLPj6+3/+FgGY3NbcwMTFNYTZU' +
          'UFAAqrhx4/7JLXvOF3oB2SAAdAMQAO1Z1S0ID826urpHn37w1a42WXzReso' +
          'uIBsexox3L2768vEZVDcMbNq0KSo2g1XRLWrJ4bkehsdju0NXV3BJCgClmB' +
          'PCbVnfrdTV4xYX/igu/AGChBnvfWOQU1e3iJIXud+wwScoeEXVZHVvUxYud' +
          'sZTuybriF+4cf2agaUlIyMj0Izzx45pamp2zH36l8/U+pqQi4sLUJyZi2vR' +
          '7NmxB1qZ/vz+y8HPD/TfyQMH/v/8eXzfPnl5eQ4BAXd3T/VD/4DiQNXXr1/' +
          'femBr2NpKRmBo/Pz5h+HPX15eXqC6Q/v3A1UAg4vhzx+geMjq8lOnTp0+ff' +
          'rep2dObbEcYnwMjAxMv37+YWRmZGFllZSSsndwAJJANgMTSByoAmjqW8avb' +
          'p2JnOIgHwMB47718148vg/hIAMJWUXHgEQoBw4YGADeHmyulF4iawAAAABJ' +
          'RU5ErkJggg=='
  $img3 = 'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAAXNSR0IArs4' +
          'c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAGSSU' +
          'RBVDhPlZK7S8NQGMXvjREESSiiYivS1BQXFUFQR+skOIngJAoW/CccHMTZ0' +
          'aFCcXHRwcG91QoWCyK2KvgsGLV1sVjrI/fpTXsrjXbxR7jcc/IdcuAL5JyD' +
          '/1A/kLte/ixmpKjSpPX6epbqB65T00ZwnNEiZ4igEsbvamNjPncbHNpS5Yg' +
          'bjCgEdDBsSg1Aci2NbCIuTuBvga/3o2cLn0ZHGKOMMYxtCFVMqHjlBEqFzK' +
          '8Cbe0zeSs+EO4vxx1SkUvyE6gUGF4wy46DKGDb8GyzwDnljFJqQ0VHqFpJf' +
          'AsqDcfrZ4yRnwK5p5v7x0g5Lmn1DopTvUvvWldZgA5WNpoZq7wCi7N5TgMT' +
          'c4dS16C+vjwYrS19/d7tVSg9AM6TF2/FDyncKART0zRPEgmOEMBYPCf7+8L' +
          'hoF2OuHECTR6PYRhHe3vctpOxmN/vF05n95QccaPYYh2Eapom5hLxuEjqug' +
          '4Icfx6KM7+FEVs3uvzjYZC4hR34VT2+hcY24nmraxUNXR0BcYm56Wo4Z+/N' +
          'wDfDojahgr8EhcAAAAASUVORK5CYII='
  
  function Get-NameSpaces([String]$root) {
    (New-Object Management.ManagementClass(
      $root, [Management.ManagementPath]'__NAMESPACE', $null
    )).GetInstances().ForEach{
      (New-Object Windows.Forms.TreeNode).Nodes.Add($_.Name)
    }
  }
  
  function Get-SubNameSpace([Windows.Forms.TreeNode[]]$nodes) {
    foreach ($nod in $nodes) {
      $nod.Nodes.Clear()
      (Get-NameSpaces "root\$($nod.FullPath)").ForEach{
        $nod.Nodes.Add($_)
      }
    }
  }
  
  function Get-ClassesNumber {
    $sbLbl_1.Text = "Classes: $($lvList1.Items.Count)"
  }
  
  function Reset-AllMessages {
    $lvList2.Items.Clear()
    ($rtbDesc, $sbLbl_2, $sbLbl_3).ForEach{$_.Text = [String]::Empty}
  }
  
  function Get-Description([Object]$object, [Boolean]$bool) {
    try {
      $ret = $(switch ($bool) {
        $true  { [Management.MethodData]$object }
        $false { [Management.PropertyData]$object }
      }).Qualifiers['Description'].Value
      $ret = "$(if (![String]::IsNullOrEmpty($ret)) {$ret} else {'n\a'})`n`n"
    }
    catch {}
    
    $ret
  }
  
  function Get-Resource([String]$base64img) {
    $ms = New-Object IO.MemoryStream(
      ($$ = [Convert]::FromBase64String($base64img)), 0, $$.Length
    )
    $img = [Drawing.Image]::FromStream($ms)
    $ms.Dispose()
    
    $img
  }
  
  $imgList = New-Object Windows.Forms.ImageList
  ($img1, $img2, $img3).ForEach{$imgList.Images.Add((Get-Resource $_))}
  
  $chClass = New-Object Windows.Forms.ColumnHeader -Property @{
    Text = 'Classes'
    Width = 615
  }
  
  $lvList1 = New-Object Windows.Forms.ListView -Property @{
    Dock = [Windows.Forms.DockStyle]::Fill
    FullRowSelect = $true
    MultiSelect = $false
    ShowItemToolTips = $true
    SmallImageList = $imgList
    Sorting = [Windows.Forms.SortOrder]::Ascending
    TileSize = New-Object Drawing.Size(270, 19)
    View = [Windows.Forms.View]::Details
  }
  [void]$lvList1.Columns.Add($chClass)
  $lvList1.Add_Click({
    Reset-AllMessages
    
    for ($i = 0; $i -lt $lvList1.Items.Count; $i++) {
      if ($lvList1.Items[$i].Selected) {
        $path = "$($cur):$($lvList1.Items[$i].Text)"
        $frmMain.Text = "$($path) - WMINavigator"
        
        $rtbDesc.SelectionFont = $fnt1
        $rtbDesc.AppendText("$($lvList1.Items[$i].Text)`n$(('-' * 100))`n")
        
        $wmi = New-Object Management.ManagementClass($path, $obj)
        $wmi.Qualifiers.ForEach{
          $itm = $lvList2.Items.Add($_.Name, 2)
          if ($_.Name -match 'Description') {
            $rtbDesc.AppendText("$($_.Value)`n`n")
            $itm.SubItems.Add('See specification')
          }
          else { $itm.SubItems.Add($_.Value.ToString()) }
          $itm.SubItems.Add($_.IsAmended.ToString())
          $itm.SubItems.Add($_.IsLocal.ToString())
          $itm.SubItems.Add($_.IsOverridable.ToString())
          $itm.SubItems.Add($_.PropagatesToInstance.ToString())
          $itm.SubItems.Add($_.PropagatesToSubclass.ToString())
        }
        
        $wmi.Methods.ForEach{
          $rtbDesc.SelectionColor = [Drawing.Color]::DarkMagenta
          $rtbDesc.SelectionFont = $fnt2
          $rtbDesc.AppendText("$($_.Name)`n")
          $rtbDesc.AppendText((Get-Description $_ $true))
        }
        
        $wmi.Properties.ForEach{
          $rtbDesc.SelectionColor = [Drawing.Color]::DarkGreen
          $rtbDesc.SelectionFont = $fnt2
          $rtbDesc.AppendText(
            "$($_.Name) [Type: $($_.Type), Local: $($_.IsLocal), Array: $($_.IsArray)]`n"
          )
          $rtbDesc.AppendText((Get-Description $_ $false))
        }
        
        $sbLbl_2.Text = "Methods: $($wmi.Methods.Count)"
        $sbLbl_3.Text = "Properties: $($wmi.Properties.Count)"
      }
    }
  })
  
  $tvRoots = New-Object Windows.Forms.TreeView -Property @{
    Dock = [Windows.Forms.DockStyle]::Fill
    ImageList = $imgList
    Sorted = $true
  }
  $tvRoots.Add_AfterExpand({Get-SubNameSpace $_.Node.Nodes})
  $tvRoots.Add_AfterSelect({
    $lvList1.Items.Clear()
    Reset-AllMessages
    
    if ($tvRoots.SelectedNode) {
      $script:cur = "root\$($tvRoots.SelectedNode.FullPath)"
      
      (New-Object Management.ManagementClass($cur, $obj)
      ).GetSubclasses($enm).ForEach{
        $lvList1.Items.Add($_.Name, 1)
      }
      
      $frmMain.Text = "$($cur) - WMINavigator"
      Get-ClassesNumber
    }
  })
  
  $scSplt2 = New-Object Windows.Forms.SplitContainer -Property @{
    Dock = [Windows.Forms.DockStyle]::Fill
    Orientation = [Windows.Forms.Orientation]::Vertical
    Panel1MinSize = 17
    SplitterDistance = 30
    SplitterWidth = 1
  }
  $scSplt2.Panel1.Controls.Add($tvRoots)
  $scSplt2.Panel2.Controls.Add($lvList1)
  
  $rtbDesc = New-Object Windows.Forms.RichTextBox -Property @{
    Dock = [Windows.Forms.DockStyle]::Fill
    ReadOnly = $true
  }
  
  $tpPage1 = New-Object Windows.Forms.TabPage -Property @{
    Text = 'Specification'
    UseVisualStyleBackColor = $true
  }
  $tpPage1.Controls.Add($rtbDesc)
  
  $chCol_1 = New-Object Windows.Forms.ColumnHeader -Property @{
    Text = 'Name'
    Width = 130
  }
  
  $chCol_2 = New-Object Windows.Forms.ColumnHeader -Property @{
    Text = 'Description'
    Width = 130
  }
  
  $chCol_3 = New-Object Windows.Forms.ColumnHeader -Property @{
    Text = 'Amended'
    Width = 70
  }
  
  $chCol_4 = New-Object Windows.Forms.ColumnHeader -Property @{
    Text = 'Local'
    Width = 70
  }
  
  $chCol_5 = New-Object Windows.Forms.ColumnHeader -Property @{
    Text = 'Overridable'
    Width = 70
  }
  
  $chCol_6 = New-Object Windows.Forms.ColumnHeader -Property @{
    Text = 'PropogatesToInstance'
    Width = 130
  }
  
  $chCol_7 = New-Object Windows.Forms.ColumnHeader -Property @{
    Text = 'PropogatesToSubclass'
    Width = 130
  }
  
  $lvList2 = New-Object Windows.Forms.ListView -Property @{
    Dock = [Windows.Forms.DockStyle]::Fill
    FullRowSelect = $true
    MultiSelect = $false
    ShowItemToolTips = $true
    SmallImageList = $imgList
    Sorting = [Windows.Forms.SortOrder]::Ascending
    View = [Windows.Forms.View]::Details
  }
  $lvList2.Columns.AddRange(@(
    $chCol_1, $chCol_2, $chCol_3, $chCol_4, $chCol_5, $chCol_6, $chCol_7
  ))
  
  $tpPage2 = New-Object Windows.Forms.TabPage -Property @{
    Text = 'Qualifiers'
    UseVisualStyleBackColor = $true
  }
  $tpPage2.Controls.Add($lvList2)
  
  $tabCtrl = New-Object Windows.Forms.TabControl -Property @{
    Dock = [Windows.Forms.DockStyle]::Fill
  }
  $tabCtrl.Controls.AddRange(@($tpPage1, $tpPage2))
  
  $scSplt1 = New-Object Windows.Forms.SplitContainer -Property @{
    Dock = [Windows.Forms.DockStyle]::Fill
    Orientation = [Windows.Forms.Orientation]::Horizontal
    SplitterDistance = 60
    SplitterWidth = 1
  }
  $scSplt1.Panel1.Controls.Add($scSplt2)
  $scSplt1.Panel2.Controls.Add($tabCtrl)
  
  $sbLbl_1 = New-Object Windows.Forms.ToolStripStatusLabel -Property @{
    AutoSize = $true
  }
  
  $sbLbl_2 = New-Object Windows.Forms.ToolStripStatusLabel -Property @{
    AutoSize = $true
    ForeColor = [Drawing.Color]::DarkMagenta
  }
  
  $sbLbl_3 = New-Object Windows.Forms.ToolStripStatusLabel -Property @{
    AutoSize = $true
    ForeColor = [Drawing.Color]::DarkGreen
  }
  
  $sbStrip = New-Object Windows.Forms.StatusStrip -Property @{
    SizingGrip = $false
  }
  $sbStrip.Items.AddRange(@($sbLbl_1, $sbLbl_2, $sbLbl_3))
  
  $frmMain = New-Object Windows.Forms.Form -Property @{
    FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedSingle
    Icon = [Drawing.Icon]::ExtractAssociatedicon("$PSHome\powershell.exe")
    Size = New-Object Drawing.Size(800, 600)
    StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
    Text = 'WMINavigator'
  }
  $frmMain.Controls.AddRange(@($scSplt1, $sbStrip))
  $frmMain.Add_Load({
    (Get-NameSpaces root).ForEach{$tvRoots.Nodes.Add($_)}
    Get-SubNameSpace $tvRoots.Nodes
    
    $script:obj = New-Object Management.ObjectGetOptions
    $script:enm = New-Object Management.EnumerationOptions
    
    $obj.UseAmendedQualifiers = $enm.EnumerateDeep = $true
    $sbLbl_1.Text = 'Ready'
  })
  
  [void]$frmMain.ShowDialog()
}
