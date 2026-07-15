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

# block_12 (5011): SANCTUM WALL - black obsidian plate, crimson circuit veins
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $edge = [Math]::Min([Math]::Min($x, 39 - $x), [Math]::Min($y, 39 - $y))
        if ($edge -eq 0) { $c = [System.Drawing.Color]::FromArgb(255, 52, 16, 26) }
        elseif ($edge -eq 1) { $c = [System.Drawing.Color]::FromArgb(255, 30, 12, 20) }
        else {
            $base = 16 + [int](5 * [Math]::Sin($x * 0.5) * [Math]::Sin($y * 0.45))
            $c = [System.Drawing.Color]::FromArgb(255, $base + 4, $base - 4, $base + 2)
        }
        $b.SetPixel($x, $y, $c)
    }
}
# crimson circuit veins (right-angle trace with nodes)
$trace = @(@(6,30),@(6,20),@(14,20),@(14,10),@(26,10),@(26,24),@(34,24))
for ($i = 0; $i -lt $trace.Count - 1; $i++) {
    $x0 = $trace[$i][0]; $y0 = $trace[$i][1]; $x1 = $trace[$i+1][0]; $y1 = $trace[$i+1][1]
    if ($x0 -eq $x1) {
        $lo = [Math]::Min($y0, $y1); $hi = [Math]::Max($y0, $y1)
        for ($y = $lo; $y -le $hi; $y++) { $b.SetPixel($x0, $y, [System.Drawing.Color]::FromArgb(255, 200, 40, 55)) }
    } else {
        $lo = [Math]::Min($x0, $x1); $hi = [Math]::Max($x0, $x1)
        for ($x = $lo; $x -le $hi; $x++) { $b.SetPixel($x, $y0, [System.Drawing.Color]::FromArgb(255, 200, 40, 55)) }
    }
}
foreach ($n in $trace) {
    $b.SetPixel($n[0], $n[1], [System.Drawing.Color]::FromArgb(255, 255, 120, 110))
}
$b.Save("$sprDir\block_12.png", [System.Drawing.Imaging.ImageFormat]::Png)
Save-Scaled $b "$sprDir\block_12_16.png"
$b.Dispose()

# block_13 (5012): SANCTUM FLOOR - ribbed dark iron, glowing crimson top seam
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        if ($y -le 1) { $c = [System.Drawing.Color]::FromArgb(255, 255, 84, 70) }
        elseif ($y -eq 2) { $c = [System.Drawing.Color]::FromArgb(255, 120, 30, 34) }
        elseif ($y -ge 38) { $c = [System.Drawing.Color]::FromArgb(255, 8, 6, 10) }
        else {
            $base = 26 - [int](($y / 39.0) * 10)
            if ((($x + 3) % 8) -lt 2) { $base -= 6 }   # vertical ribs
            if (($y % 9) -eq 5) { $base += 4 }
            $c = [System.Drawing.Color]::FromArgb(255, $base + 6, $base, $base + 4)
        }
        $b.SetPixel($x, $y, $c)
    }
}
# seam segment gaps
for ($x = 0; $x -lt 40; $x++) {
    if (($x % 10) -ge 8) {
        $b.SetPixel($x, 0, [System.Drawing.Color]::FromArgb(255, 90, 24, 26))
        $b.SetPixel($x, 1, [System.Drawing.Color]::FromArgb(255, 90, 24, 26))
    }
}
$b.Save("$sprDir\block_13.png", [System.Drawing.Imaging.ImageFormat]::Png)
Save-Scaled $b "$sprDir\block_13_16.png"
$b.Dispose()

# block_14 (5013): RUNE CORE - dark plate with a glowing crimson rune ring
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $edge = [Math]::Min([Math]::Min($x, 39 - $x), [Math]::Min($y, 39 - $y))
        if ($edge -eq 0) { $c = [System.Drawing.Color]::FromArgb(255, 60, 18, 28) }
        else {
            $base = 14 + $edge
            if ($base -gt 22) { $base = 22 }
            $c = [System.Drawing.Color]::FromArgb(255, $base + 4, $base - 2, $base + 2)
        }
        $dx = $x - 19.5; $dy = $y - 19.5
        $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
        if ($d -ge 10.0 -and $d -le 12.6) { $c = [System.Drawing.Color]::FromArgb(255, 235, 60, 70) }
        elseif ($d -ge 12.6 -and $d -le 14.0) { $c = [System.Drawing.Color]::FromArgb(255, 96, 26, 32) }
        elseif ($d -lt 3.0) { $c = [System.Drawing.Color]::FromArgb(255, 255, 150, 130) }
        $b.SetPixel($x, $y, $c)
    }
}
# rune glyph: crossing strokes inside the ring
for ($i = -7; $i -le 7; $i++) {
    $b.SetPixel(20 + $i, 20, [System.Drawing.Color]::FromArgb(255, 220, 70, 78))
    $b.SetPixel(20, 20 + $i, [System.Drawing.Color]::FromArgb(255, 220, 70, 78))
}
for ($i = -4; $i -le 4; $i++) {
    $b.SetPixel(20 + $i, 20 - $i, [System.Drawing.Color]::FromArgb(255, 170, 46, 56))
}
# outer corner studs
foreach ($rx in 3, 36) { foreach ($ry in 3, 36) {
    $b.SetPixel($rx, $ry, [System.Drawing.Color]::FromArgb(255, 255, 110, 100))
} }
$b.Save("$sprDir\block_14.png", [System.Drawing.Imaging.ImageFormat]::Png)
Save-Scaled $b "$sprDir\block_14_16.png"
$b.Dispose()

# block_15 (5014): VOID FILL - black-violet depth with dying embers
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $base = 8 + [int](3 * [Math]::Sin($x * 0.23 + $y * 0.31))
        $c = [System.Drawing.Color]::FromArgb(255, $base + 2, $base - 3, $base + 5)
        $b.SetPixel($x, $y, $c)
    }
}
$emb = @(@(7,9),@(21,5),@(33,14),@(12,26),@(28,31),@(36,35),@(4,36),@(18,17))
foreach ($e in $emb) {
    $b.SetPixel($e[0], $e[1], [System.Drawing.Color]::FromArgb(255, 110, 30, 36))
}
$b.SetPixel(21, 6, [System.Drawing.Color]::FromArgb(255, 60, 18, 22))
$b.SetPixel(12, 27, [System.Drawing.Color]::FromArgb(255, 60, 18, 22))
$b.Save("$sprDir\block_15.png", [System.Drawing.Imaging.ImageFormat]::Png)
Save-Scaled $b "$sprDir\block_15_16.png"
$b.Dispose()

# block_16 (5015): WARDEN ENERGY - crimson/violet energy for the buttress curves
$b = New-Object System.Drawing.Bitmap(40, 40)
for ($y = 0; $y -lt 40; $y++) {
    for ($x = 0; $x -lt 40; $x++) {
        $edge = [Math]::Min([Math]::Min($x, 39 - $x), [Math]::Min($y, 39 - $y))
        if ($edge -eq 0) { $c = [System.Drawing.Color]::FromArgb(255, 16, 6, 10) }
        elseif ($edge -eq 1) { $c = [System.Drawing.Color]::FromArgb(255, 150, 36, 60) }
        else {
            $base = 22 + [int](7 * [Math]::Sin(($x - $y) * 0.26))
            $c = [System.Drawing.Color]::FromArgb(255, [int]($base * 1.35), [int]($base * 0.4), [int]($base * 0.75))
        }
        $b.SetPixel($x, $y, $c)
    }
}
# white-hot core vein
for ($x = 2; $x -lt 38; $x++) {
    $vy = 20 + [int](9 * [Math]::Sin($x * 0.5 + 1.2))
    if ($vy -ge 2 -and $vy -lt 38) {
        $b.SetPixel($x, $vy, [System.Drawing.Color]::FromArgb(255, 255, 120, 90))
        if ($vy + 1 -lt 38) { $b.SetPixel($x, $vy + 1, [System.Drawing.Color]::FromArgb(255, 140, 40, 50)) }
    }
}
# violet cross vein
for ($y = 2; $y -lt 38; $y++) {
    $vx = 20 + [int](10 * [Math]::Sin($y * 0.42 + 3.1))
    if ($vx -ge 2 -and $vx -lt 38) {
        $b.SetPixel($vx, $y, [System.Drawing.Color]::FromArgb(255, 190, 80, 255))
    }
}
$b.Save("$sprDir\block_16.png", [System.Drawing.Imaging.ImageFormat]::Png)
Save-Scaled $b "$sprDir\block_16_16.png"
$b.Dispose()

Write-Output "Boss sanctum sprites written (block_12..block_16)"
