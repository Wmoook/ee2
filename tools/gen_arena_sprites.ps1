$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$sprDir = 'C:\Users\super\ee2\assets\sprites\NEW_BLOCK_SPRITE'

function Save-Scaled([System.Drawing.Bitmap]$bmp, [string]$path16) {
    $small = New-Object System.Drawing.Bitmap(16, 16)
    $g = [System.Drawing.Graphics]::FromImage($small)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($bmp, 0, 0, 16, 16)
    $g.Dispose()
    $small.Save($path16, [System.Drawing.Imaging.ImageFormat]::Png)
    $small.Dispose()
}

# block_8 (5007): FLOOR PLATE - brushed steel blue with beveled edge + cyan seam
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $edge = [Math]::Min([Math]::Min($x, 39 - $x), [Math]::Min($y, 39 - $y))
        if ($x -le 1 -or $y -le 1) {
            if ($edge -eq 0) { $c = [System.Drawing.Color]::FromArgb(255, 74, 88, 108) } else { $c = [System.Drawing.Color]::FromArgb(255, 62, 74, 92) }
        }
        elseif ($x -ge 38 -or $y -ge 38) {
            $c = [System.Drawing.Color]::FromArgb(255, 18, 22, 30)
        }
        else {
            $base = 46 - [int](($y / 39.0) * 12)
            # brushed lines
            if (($y % 6) -eq 3) { $base += 5 }
            $c = [System.Drawing.Color]::FromArgb(255, $base, $base + 7, $base + 18)
        }
        $b.SetPixel($x, $y, $c)
    }
}
# cyan center seam with segment gaps
for ($x = 4; $x -lt 36; $x++) {
    if (($x % 10) -lt 7) {
        $b.SetPixel($x, 19, [System.Drawing.Color]::FromArgb(255, 55, 220, 245))
        $b.SetPixel($x, 20, [System.Drawing.Color]::FromArgb(255, 24, 96, 116))
    }
}
# corner bolts
foreach ($rx in 4, 34) { foreach ($ry in 4, 34) {
    $b.SetPixel($rx, $ry, [System.Drawing.Color]::FromArgb(255, 130, 200, 220))
    $b.SetPixel($rx + 1, $ry, [System.Drawing.Color]::FromArgb(255, 90, 140, 160))
    $b.SetPixel($rx, $ry + 1, [System.Drawing.Color]::FromArgb(255, 90, 140, 160))
} }
$b.Save("$sprDir\block_8.png", [System.Drawing.Imaging.ImageFormat]::Png)
Save-Scaled $b "$sprDir\block_8_16.png"
$b.Dispose()

# block_9 (5008): DARK FILL - deep base with faint grid
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $c = [System.Drawing.Color]::FromArgb(255, 14, 17, 24)
        if (($x % 10) -eq 0 -or ($y % 10) -eq 0) { $c = [System.Drawing.Color]::FromArgb(255, 22, 27, 38) }
        if (($x % 20) -eq 10 -and ($y % 20) -eq 10) { $c = [System.Drawing.Color]::FromArgb(255, 36, 46, 62) }
        $b.SetPixel($x, $y, $c)
    }
}
$b.Save("$sprDir\block_9.png", [System.Drawing.Imaging.ImageFormat]::Png)
Save-Scaled $b "$sprDir\block_9_16.png"
$b.Dispose()

# block_10 (5009): ENERGY BLOCK (curves) - dark violet with magenta/cyan veins
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $edge = [Math]::Min([Math]::Min($x, 39 - $x), [Math]::Min($y, 39 - $y))
        if ($edge -eq 0) { $c = [System.Drawing.Color]::FromArgb(255, 10, 6, 16) }
        elseif ($edge -eq 1) { $c = [System.Drawing.Color]::FromArgb(255, 120, 40, 150) }
        else {
            $base = 24 + [int](6 * [Math]::Sin(($x + $y) * 0.22))
            $c = [System.Drawing.Color]::FromArgb(255, $base, [int]($base * 0.55), [int]($base * 1.5))
        }
        $b.SetPixel($x, $y, $c)
    }
}
# magenta vein (zigzag diagonal)
for ($x = 2; $x -lt 38; $x++) {
    $vy = 20 + [int](10 * [Math]::Sin($x * 0.45))
    if ($vy -ge 2 -and $vy -lt 38) {
        $b.SetPixel($x, $vy, [System.Drawing.Color]::FromArgb(255, 255, 70, 210))
        if ($vy + 1 -lt 38) { $b.SetPixel($x, $vy + 1, [System.Drawing.Color]::FromArgb(255, 120, 30, 100)) }
    }
}
# cyan cross vein
for ($y = 2; $y -lt 38; $y++) {
    $vx = 20 + [int](11 * [Math]::Sin($y * 0.4 + 2.0))
    if ($vx -ge 2 -and $vx -lt 38) {
        $b.SetPixel($vx, $y, [System.Drawing.Color]::FromArgb(255, 60, 220, 255))
    }
}
$b.Save("$sprDir\block_10.png", [System.Drawing.Imaging.ImageFormat]::Png)
Save-Scaled $b "$sprDir\block_10_16.png"
$b.Dispose()

# block_11 (5010): PLASMA SPIKES - transparent bg, glowing triangles
$b = New-Object System.Drawing.Bitmap(40, 40)
# 4 spikes, each 10px wide, bottom-anchored
for ($s = 0; $s -lt 4; $s++) {
    $cx = $s * 10 + 5
    for ($y = 8; $y -lt 40; $y++) {
        $half = [int](($y - 8) * 5.0 / 32.0)
        for ($dx = -$half; $dx -le $half; $dx++) {
            $x = $cx + $dx
            if ($x -lt 0 -or $x -ge 40) { continue }
            $t = ($y - 8) / 32.0
            $r = [int](255 - 90 * $t)
            $g2 = [int](140 - 100 * $t)
            $bl = [int](30 - 20 * $t)
            $c = [System.Drawing.Color]::FromArgb(255, $r, [Math]::Max($g2, 20), [Math]::Max($bl, 8))
            # darker core stripe
            if ([Math]::Abs($dx) -le 0) { $c = [System.Drawing.Color]::FromArgb(255, 255, [int](180 - 80 * $t), 40) }
            $b.SetPixel($x, $y, $c)
        }
    }
    # white-hot tip
    $b.SetPixel($cx, 8, [System.Drawing.Color]::FromArgb(255, 255, 240, 200))
    $b.SetPixel($cx, 9, [System.Drawing.Color]::FromArgb(255, 255, 210, 120))
    # floating ember
    $ex = $cx + (($s * 7) % 5) - 2
    $ey = 3 + (($s * 5) % 4)
    if ($ex -ge 0 -and $ex -lt 40) { $b.SetPixel($ex, $ey, [System.Drawing.Color]::FromArgb(255, 255, 170, 60)) }
}
$b.Save("$sprDir\block_11.png", [System.Drawing.Imaging.ImageFormat]::Png)
Save-Scaled $b "$sprDir\block_11_16.png"
$b.Dispose()

Write-Output "Arena sprites written"
