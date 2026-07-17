# CURVES tab ribbons only (block_59..68) — fixed version: the mirror wrapper
# uses GetNewClosure so the inner scriptblock resolves correctly (the original
# nested dynamic-scope lookup recursed onto itself).
Add-Type -AssemblyName System.Drawing
$dir = "C:\Users\super\ee2\assets\sprites\NEW_BLOCK_SPRITE"

function Clamp([double]$v) { if ($v -lt 0) { return 0 }; if ($v -gt 255) { return 255 }; return [int]$v }
function C([double]$r, [double]$g, [double]$b) { return [System.Drawing.Color]::FromArgb(255, (Clamp $r), (Clamp $g), (Clamp $b)) }
function Cyl([double]$y) { return 0.52 + 0.48 * [math]::Sin([math]::PI * $y / 39.0) }

function Save-Block([System.Drawing.Bitmap]$bmp, [int]$n) {
    $bmp.Save("$dir\block_$n.png")
    $b16 = New-Object System.Drawing.Bitmap(16, 16)
    $g16 = [System.Drawing.Graphics]::FromImage($b16)
    $g16.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g16.DrawImage($bmp, (New-Object System.Drawing.Rectangle(0, 0, 16, 16)))
    $g16.Dispose()
    $b16.Save("$dir\block_$n`_16.png")
    $b16.Dispose()
    $bmp.Dispose()
    Write-Output "block_$n done"
}

function New-CurveBlock([int]$n, [scriptblock]$cfn) {
    $bmp = New-Object System.Drawing.Bitmap(40, 40)
    for ($y = 0; $y -lt 40; $y++) {
        for ($x = 0; $x -lt 40; $x++) {
            $sx = $x
            if ($sx -ge 20) { $sx = 39 - $sx }
            $bmp.SetPixel($x, $y, (& $cfn $sx $y))
        }
    }
    Save-Block $bmp $n
}

# 59 RAINBOW RIBBON
New-CurveBlock 59 {
    param($sx, $y)
    $bands = @(@(255, 70, 70), @(255, 160, 40), @(255, 230, 60), @(80, 220, 90), @(70, 150, 255), @(170, 90, 255))
    $bi = [math]::Floor($y / 6.67); if ($bi -gt 5) { $bi = 5 }
    $c = $bands[$bi]
    $m = 0.75 + 0.25 * (Cyl $y)
    if ($y -le 1) { return C 255 255 255 }
    C ($c[0] * $m) ($c[1] * $m) ($c[2] * $m)
}

# 60 NEON TUBE CYAN
New-CurveBlock 60 {
    param($sx, $y)
    $d = [math]::Abs($y - 19.5)
    if ($d -lt 3) { return C 235 255 255 }
    if ($d -lt 7) { return C 60 (230 - $d * 8) 255 }
    if ($d -lt 13) { return C 16 (110 - $d * 4) (160 - $d * 3) }
    $tick = 0; if (($sx % 10) -lt 1 -and $d -lt 17) { $tick = 26 }
    C (6 + $tick) (26 + $tick * 2) (38 + $tick * 2)
}

# 61 NEON TUBE MAGENTA
New-CurveBlock 61 {
    param($sx, $y)
    $d = [math]::Abs($y - 19.5)
    if ($d -lt 3) { return C 255 240 255 }
    if ($d -lt 7) { return C 255 60 (230 - $d * 6) }
    if ($d -lt 13) { return C (150 - $d * 4) 18 (130 - $d * 3) }
    $tick = 0; if (($sx % 10) -lt 1 -and $d -lt 17) { $tick = 26 }
    C (34 + $tick * 2) (8 + $tick) (30 + $tick * 2)
}

# 62 GOLD RAIL
New-CurveBlock 62 {
    param($sx, $y)
    $m = Cyl $y
    $r = 250 * $m; $g = 195 * $m; $b = 60 * $m
    if ($y -ge 4 -and $y -le 8) { $r = 255; $g = 240; $b = 150 }
    if ($y -ge 34) { $r *= 0.6; $g *= 0.6; $b *= 0.6 }
    $rd = [math]::Sqrt(($sx - 10) * ($sx - 10) + ($y - 20) * ($y - 20))
    if ($rd -lt 2.4) { $r = 140; $g = 100; $b = 30 }
    elseif ($rd -lt 3.4) { $r = 255; $g = 235; $b = 160 }
    C $r $g $b
}

# 63 STEEL PIPE
New-CurveBlock 63 {
    param($sx, $y)
    $m = Cyl $y
    $v = 205 * $m
    if ($y -ge 5 -and $y -le 9) { $v = 235 }
    $seam = 0; if ($sx -lt 1) { $seam = -40 }
    $brush = (($y * 3 + $sx) % 7) - 3
    C ($v + $seam + $brush) ($v + $seam + $brush + 4) ($v + $seam + $brush + 10)
}

# 64 CANDY RIBBON
New-CurveBlock 64 {
    param($sx, $y)
    $m = 0.72 + 0.28 * (Cyl $y)
    $stripe = [math]::Floor(($sx + 2) / 5) % 2
    if ($stripe -eq 0) { C (240 * $m) (60 * $m) (80 * $m) } else { C (255 * $m) (250 * $m) (250 * $m) }
}

# 65 LAVA FLOW RIBBON
New-CurveBlock 65 {
    param($sx, $y)
    $d = [math]::Abs($y - 19.5)
    if ($d -gt 15) { return C 40 26 24 }
    if ($d -gt 11) { return C 110 40 20 }
    $core = [math]::Sin($sx * 0.5) * 3
    if ($d -lt (4 + $core)) { return C 255 (220 - $d * 10) 60 }
    C 245 (110 - $d * 4) 24
}

# 66 ICE RIBBON
New-CurveBlock 66 {
    param($sx, $y)
    $m = Cyl $y
    $r = 170 * $m + 40; $g = 216 * $m + 30; $b = 250 * $m + 5
    if ($y -ge 3 -and $y -le 7) { $r = 240; $g = 250; $b = 255 }
    $sp = [math]::Sqrt(($sx - 13) * ($sx - 13) + ($y - 24) * ($y - 24))
    if ($sp -lt 1.2) { $r = 255; $g = 255; $b = 255 }
    C $r $g $b
}

# 67 JUNGLE VINE
New-CurveBlock 67 {
    param($sx, $y)
    $m = Cyl $y
    $braid = [math]::Sin(($y * 0.55) + ($sx * 0.5)) + [math]::Sin(($y * 0.55) - ($sx * 0.5))
    $r = 40 + $braid * 10; $g = 130 * $m + $braid * 16 + 20; $b = 30 + $braid * 6
    $ld = [math]::Sqrt(($sx - 6) * ($sx - 6) + ($y - 8) * ($y - 8))
    if ($ld -lt 3.2) { $r = 70; $g = 200; $b = 60 }
    C $r $g $b
}

# 68 STARLIGHT
New-CurveBlock 68 {
    param($sx, $y)
    $m = 0.55 + 0.45 * (Cyl $y)
    $r = 34 * $m; $g = 20 * $m; $b = 78 * $m
    foreach ($st in @(@(8, 12, 2.0), @(16, 26, 1.4), @(4, 30, 1.0), @(13, 6, 1.2))) {
        $d = [math]::Abs($sx - $st[0]) + [math]::Abs($y - $st[1])
        if ($d -lt $st[2]) { $r = 255; $g = 250; $b = 255 }
        elseif ($d -lt $st[2] + 2.4) { $r += 90; $g += 70; $b += 130 }
    }
    C $r $g $b
}

Write-Output "CURVES DONE"
