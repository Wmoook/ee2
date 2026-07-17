# EE COMBAT block packs: CANDY / NEON / CASTLE / FROST / MAGMA + CURVES tab.
# Generates block_31.png .. block_68.png (40x40) + _16 versions into
# assets/sprites/NEW_BLOCK_SPRITE/. Curve ribbons (block_59..68) are built
# HORIZONTALLY SYMMETRIC so the curve mesh's mirrored tiling is seamless.
Add-Type -AssemblyName System.Drawing
$dir = "C:\Users\super\ee2\assets\sprites\NEW_BLOCK_SPRITE"

function Clamp([double]$v) { if ($v -lt 0) { return 0 }; if ($v -gt 255) { return 255 }; return [int]$v }
function C([double]$r, [double]$g, [double]$b) { return [System.Drawing.Color]::FromArgb(255, (Clamp $r), (Clamp $g), (Clamp $b)) }

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

# Standard bevel: light top/left, dark bottom/right (matches existing packs)
function Bevel([System.Drawing.Bitmap]$bmp, [double]$amt) {
    for ($i = 0; $i -lt 40; $i++) {
        foreach ($e in @(@(0, $i, 1), @($i, 0, 1), @(1, $i, 0.5), @($i, 1, 0.5))) {
            $p = $bmp.GetPixel($e[0], $e[1])
            $bmp.SetPixel($e[0], $e[1], (C ($p.R + $amt * $e[2]) ($p.G + $amt * $e[2]) ($p.B + $amt * $e[2])))
        }
        foreach ($e in @(@(39, $i, 1), @($i, 39, 1), @(38, $i, 0.5), @($i, 38, 0.5))) {
            $p = $bmp.GetPixel($e[0], $e[1])
            $bmp.SetPixel($e[0], $e[1], (C ($p.R - $amt * $e[2]) ($p.G - $amt * $e[2]) ($p.B - $amt * $e[2])))
        }
    }
}

function New-BlockFromFunc([int]$n, [scriptblock]$fn, [bool]$bevel = $true, [double]$bevelAmt = 34) {
    $bmp = New-Object System.Drawing.Bitmap(40, 40)
    $rng = New-Object System.Random($n * 7919)
    for ($y = 0; $y -lt 40; $y++) {
        for ($x = 0; $x -lt 40; $x++) {
            $col = & $fn $x $y $rng
            $bmp.SetPixel($x, $y, $col)
        }
    }
    if ($bevel) { Bevel $bmp $bevelAmt }
    Save-Block $bmp $n
}

# ===================== CANDY (5030-5035 -> block_31..36) =====================

# 31 BUBBLEGUM — glossy pink with lighter blobs
New-BlockFromFunc 31 {
    param($x, $y, $rng)
    $r = 245.0; $g = 120.0; $b = 175.0
    foreach ($blob in @(@(10, 12, 7), @(28, 8, 5), @(22, 27, 8), @(7, 30, 5))) {
        $d = [math]::Sqrt(($x - $blob[0]) * ($x - $blob[0]) + ($y - $blob[1]) * ($y - $blob[1]))
        if ($d -lt $blob[2]) { $r += 18; $g += 24; $b += 20 }
    }
    $gl = (38 - $x - $y) * 0.9; if ($gl -lt 0) { $gl = 0 }
    C ($r + $gl * 0.4) ($g + $gl * 0.5) ($b + $gl * 0.45)
}

# 32 CANDY CANE — bold vertical red/white stripes, glossy
New-BlockFromFunc 32 {
    param($x, $y, $rng)
    $stripe = [math]::Floor($x / 5) % 2
    $shine = 12 * [math]::Sin([math]::PI * $y / 39.0)
    if ($stripe -eq 0) { C (235 + $shine) (40 + $shine) (60 + $shine) } else { C (250 + $shine) (245 + $shine) (245 + $shine) }
}

# 33 CHOCOLATE — dark squares with grooves
New-BlockFromFunc 33 {
    param($x, $y, $rng)
    $gx = $x % 20; $gy = $y % 20
    $r = 96.0; $g = 58.0; $b = 30.0
    if ($gx -lt 2 -or $gy -lt 2) { $r = 60; $g = 34; $b = 16 }
    elseif ($gx -lt 4 -and $gy -ge 2) { $r = 122; $g = 78; $b = 44 }
    elseif ($gy -lt 4 -and $gx -ge 2) { $r = 118; $g = 74; $b = 42 }
    C $r $g $b
}

# 34 MINT SWIRL — pale mint with cream spiral arcs
New-BlockFromFunc 34 {
    param($x, $y, $rng)
    $dx = $x - 19.5; $dy = $y - 19.5
    $ang = [math]::Atan2($dy, $dx); $d = [math]::Sqrt($dx * $dx + $dy * $dy)
    $sw = [math]::Sin($ang * 2.0 + $d * 0.55)
    if ($sw -gt 0.45) { C 226 250 238 } else { C (140 + $d * 1.2) (226 + $d * 0.4) (186 + $d * 0.8) }
}

# 35 BERRY JELLY — wobbly purple with seeds + gloss
New-BlockFromFunc 35 {
    param($x, $y, $rng)
    $w = [math]::Sin($x * 0.5) * 2 + [math]::Sin($y * 0.4) * 2
    $r = 130 + $w * 6; $g = 70 + $w * 4; $b = 200 + $w * 5
    foreach ($seed in @(@(12, 15), @(25, 10), @(30, 26), @(9, 29), @(20, 21))) {
        if ([math]::Abs($x - $seed[0]) -le 1 -and [math]::Abs($y - $seed[1]) -le 1) { $r = 60; $g = 20; $b = 90 }
    }
    if (($x + $y) -lt 20) { $r += 30; $g += 26; $b += 24 }
    C $r $g $b
}

# 36 GOLDEN WAFER — tan layers with criss-cross pattern
New-BlockFromFunc 36 {
    param($x, $y, $rng)
    $r = 222.0; $g = 172.0; $b = 100.0
    if (($y % 8) -lt 2) { $r = 190; $g = 138; $b = 70 }
    if (($x % 8) -lt 1) { $r -= 20; $g -= 18; $b -= 12 }
    if ((($x + $y) % 16) -lt 1) { $r += 22; $g += 20; $b += 12 }
    C $r $g $b
}

# ===================== NEON (5036-5041 -> block_37..42) =====================

# 37 TRON PANEL — near-black with cyan edge glow + inner line
New-BlockFromFunc 37 {
    param($x, $y, $rng)
    $edge = [math]::Min([math]::Min($x, 39 - $x), [math]::Min($y, 39 - $y))
    $r = 8.0; $g = 14.0; $b = 24.0
    if ($edge -eq 2 -or $edge -eq 3) { $r = 40; $g = 220; $b = 255 }
    elseif ($edge -lt 2) { $r = 16; $g = 90; $b = 120 }
    elseif ($edge -lt 7) { $g += (7 - $edge) * 14; $b += (7 - $edge) * 20 }
    if ($x -ge 12 -and $x -le 27 -and ($y -eq 19 -or $y -eq 20)) { $r = 30; $g = 170; $b = 210 }
    C $r $g $b
} $false

# 38 CIRCUIT MAGENTA — dark with magenta traces and nodes
New-BlockFromFunc 38 {
    param($x, $y, $rng)
    $r = 16.0; $g = 8.0; $b = 20.0
    $on = $false
    if ($y -eq 8 -and $x -ge 4 -and $x -le 30) { $on = $true }
    if ($x -eq 30 -and $y -ge 8 -and $y -le 24) { $on = $true }
    if ($y -eq 24 -and $x -ge 12 -and $x -le 30) { $on = $true }
    if ($x -eq 12 -and $y -ge 24 -and $y -le 34) { $on = $true }
    if ($x -eq 4 -and $y -ge 8 -and $y -le 16) { $on = $true }
    if ($y -eq 16 -and $x -ge 4 -and $x -le 20) { $on = $true }
    if ($on) { $r = 255; $g = 60; $b = 200 }
    foreach ($node in @(@(4, 8), @(30, 8), @(30, 24), @(12, 34), @(20, 16))) {
        if ([math]::Abs($x - $node[0]) -le 1 -and [math]::Abs($y - $node[1]) -le 1) { $r = 255; $g = 190; $b = 240 }
    }
    C $r $g $b
} $false

# 39 HEXCORE GREEN — dark with glowing hexagon
New-BlockFromFunc 39 {
    param($x, $y, $rng)
    $dx = [math]::Abs($x - 19.5); $dy = [math]::Abs($y - 19.5)
    $hex = [math]::Max($dx * 0.866 + $dy * 0.5, $dy)
    $r = 6.0; $g = 18.0; $b = 10.0
    if ([math]::Abs($hex - 12) -lt 1.3) { $r = 80; $g = 255; $b = 120 }
    elseif ([math]::Abs($hex - 12) -lt 3.5) { $g = 120; $b = 40 }
    elseif ($hex -lt 12) { $g = 60 + (12 - $hex) * 4; $b = 20 }
    C $r $g $b
} $false

# 40 AMBER SCAN — warm dark with horizontal scanlines
New-BlockFromFunc 40 {
    param($x, $y, $rng)
    $r = 26.0; $g = 16.0; $b = 6.0
    if (($y % 6) -eq 0) { $r = 255; $g = 170; $b = 40 }
    elseif (($y % 6) -eq 1) { $r = 140; $g = 90; $b = 24 }
    $fade = 1.0 - ($y / 60.0)
    C ($r * $fade + 10) ($g * $fade + 4) ($b * $fade)
} $false

# 41 VIOLET PULSE — concentric diamond rings
New-BlockFromFunc 41 {
    param($x, $y, $rng)
    $d = [math]::Abs($x - 19.5) + [math]::Abs($y - 19.5)
    $ring = $d % 8
    $r = 20.0; $g = 8.0; $b = 34.0
    if ($ring -lt 1.4) { $r = 190; $g = 90; $b = 255 }
    elseif ($ring -lt 3) { $r = 80; $g = 30; $b = 130 }
    C $r $g $b
} $false

# 42 GRID STROBE — dark blue with white grid + corner studs
New-BlockFromFunc 42 {
    param($x, $y, $rng)
    $r = 10.0; $g = 14.0; $b = 30.0
    if (($x % 10) -lt 1 -or ($y % 10) -lt 1) { $r = 170; $g = 200; $b = 255 }
    if (($x % 10) -lt 2 -and ($y % 10) -lt 2) { $r = 255; $g = 255; $b = 255 }
    C $r $g $b
} $false

# ===================== CASTLE (5042-5047 -> block_43..48) =====================

# 43 STONE BRICK — offset courses with mortar
New-BlockFromFunc 43 {
    param($x, $y, $rng)
    $row = [math]::Floor($y / 10)
    $ox = if ($row % 2 -eq 0) { 0 } else { 10 }
    $bx = ($x + $ox) % 20
    $shade = ((($row * 13) + [math]::Floor(($x + $ox) / 20) * 7) % 5) * 8
    $r = 128.0 + $shade; $g = 126.0 + $shade; $b = 130.0 + $shade
    if (($y % 10) -ge 8 -or $bx -ge 18) { $r = 74; $g = 72; $b = 78 }
    C $r $g $b
}

# 44 COBBLESTONE — rounded stone blobs
New-BlockFromFunc 44 {
    param($x, $y, $rng)
    $r = 70.0; $g = 68.0; $b = 74.0
    foreach ($st in @(@(8, 7, 7, 20), @(24, 6, 8, 8), @(35, 12, 6, 14), @(6, 22, 7, 4), @(19, 20, 8, 24), @(33, 27, 7, 0), @(10, 34, 7, 12), @(25, 34, 6, 18))) {
        $d = [math]::Sqrt(($x - $st[0]) * ($x - $st[0]) + ($y - $st[1]) * ($y - $st[1]))
        if ($d -lt $st[2]) {
            $v = 120 + $st[3] - $d * 5
            $r = $v; $g = $v - 2; $b = $v + 3
        }
    }
    C $r $g $b
}

# 45 MOSSY BRICK — stone brick with moss creep
New-BlockFromFunc 45 {
    param($x, $y, $rng)
    $row = [math]::Floor($y / 10)
    $ox = if ($row % 2 -eq 0) { 0 } else { 10 }
    $bx = ($x + $ox) % 20
    $mortar = (($y % 10) -ge 8 -or $bx -ge 18)
    $r = 118.0; $g = 120.0; $b = 116.0
    if ($mortar) { $r = 66; $g = 68; $b = 64 }
    $m = [math]::Sin($x * 0.9 + 1) + [math]::Sin($y * 0.7) + ($(if ($mortar) { 1.1 } else { 0 }))
    if ($m -gt 1.2) { $r = 70; $g = 128; $b = 52 }
    if ($m -gt 1.9) { $r = 92; $g = 158; $b = 66 }
    C $r $g $b
}

# 46 CRACKED KEEP — stone with a dark lightning crack
New-BlockFromFunc 46 {
    param($x, $y, $rng)
    $shade = ([math]::Sin($x * 0.35) + [math]::Sin($y * 0.3)) * 7
    $r = 120.0 + $shade; $g = 118.0 + $shade; $b = 124.0 + $shade
    $cx = 20 + [math]::Sin($y * 0.55) * 6 + $(if ($y -gt 20) { ($y - 20) * 0.5 } else { 0 })
    if ([math]::Abs($x - $cx) -lt 1.4) { $r = 40; $g = 38; $b = 44 }
    elseif ([math]::Abs($x - $cx) -lt 2.6) { $r -= 26; $g -= 26; $b -= 26 }
    C $r $g $b
}

# 47 MARBLE — pale with soft veins
New-BlockFromFunc 47 {
    param($x, $y, $rng)
    $v = [math]::Sin($x * 0.24 + $y * 0.31) + [math]::Sin($x * 0.11 - $y * 0.21 + 2)
    $r = 226.0; $g = 226.0; $b = 232.0
    if ([math]::Abs($v) -lt 0.14) { $r = 176; $g = 180; $b = 196 }
    elseif ([math]::Abs($v - 0.9) -lt 0.1) { $r = 205; $g = 206; $b = 216 }
    C $r $g $b
}

# 48 ROYAL INLAY — stone with gold trim + center diamond
New-BlockFromFunc 48 {
    param($x, $y, $rng)
    $edge = [math]::Min([math]::Min($x, 39 - $x), [math]::Min($y, 39 - $y))
    $r = 108.0; $g = 106.0; $b = 114.0
    if ($edge -ge 3 -and $edge -le 5) { $r = 235; $g = 185; $b = 60 }
    $d = [math]::Abs($x - 19.5) + [math]::Abs($y - 19.5)
    if ($d -lt 7) { $r = 244; $g = 200; $b = 80 }
    if ($d -lt 4) { $r = 255; $g = 232; $b = 140 }
    C $r $g $b
}

# ===================== FROST (5048-5052 -> block_49..53) =====================

# 49 ICE GLASS — pale blue with diagonal sheen + cracks
New-BlockFromFunc 49 {
    param($x, $y, $rng)
    $r = 168.0; $g = 214.0; $b = 244.0
    $sheen = ($x + $y) % 26
    if ($sheen -lt 5) { $r += 40; $g += 30; $b += 11 }
    if ([math]::Abs(($x - 8) - ($y * 0.7)) -lt 0.9) { $r = 120; $g = 170; $b = 210 }
    if ([math]::Abs((39 - $x - 4) - ($y * 0.5)) -lt 0.7) { $r = 130; $g = 180; $b = 216 }
    C $r $g $b
}

# 50 PACKED SNOW — lumpy white
New-BlockFromFunc 50 {
    param($x, $y, $rng)
    $n = [math]::Sin($x * 0.9) * [math]::Sin($y * 0.8 + 1) + [math]::Sin(($x + $y) * 0.5)
    $v = 236 + $n * 9 - ($y * 0.45)
    C ($v - 6) ($v - 2) 255
}

# 51 FROST BRICK — icy bricks with rime edges
New-BlockFromFunc 51 {
    param($x, $y, $rng)
    $row = [math]::Floor($y / 10)
    $ox = if ($row % 2 -eq 0) { 0 } else { 10 }
    $bx = ($x + $ox) % 20
    $r = 140.0; $g = 190.0; $b = 232.0
    if (($y % 10) -ge 8 -or $bx -ge 18) { $r = 210; $g = 236; $b = 252 }
    elseif ($bx -lt 2 -or ($y % 10) -lt 2) { $r = 176; $g = 216; $b = 244 }
    C $r $g $b
}

# 52 GLACIER DEEP — vertical gradient with bubbles
New-BlockFromFunc 52 {
    param($x, $y, $rng)
    $t = $y / 39.0
    $r = 190 - $t * 130; $g = 226 - $t * 120; $b = 250 - $t * 60
    foreach ($bub in @(@(9, 12, 2), @(28, 20, 3), @(16, 30, 2), @(33, 34, 2), @(6, 26, 1))) {
        $d = [math]::Sqrt(($x - $bub[0]) * ($x - $bub[0]) + ($y - $bub[1]) * ($y - $bub[1]))
        if ([math]::Abs($d - $bub[2]) -lt 0.9) { $r += 46; $g += 36; $b += 16 }
    }
    C $r $g $b
}

# 53 AURORA CRYSTAL — faceted cyan/violet shards
New-BlockFromFunc 53 {
    param($x, $y, $rng)
    $f1 = ($x * 0.8 + $y * 0.55) % 16
    $f2 = ($x * 0.5 - $y * 0.8 + 40) % 14
    $r = 120.0; $g = 110.0; $b = 210.0
    if ($f1 -lt 6) { $r = 90; $g = 220; $b = 240 }
    if ($f2 -lt 4) { $r = ($r + 190) / 2; $g = ($g + 120) / 2; $b = 255 }
    if ($f1 -ge 5.2 -and $f1 -lt 6) { $r = 240; $g = 250; $b = 255 }
    C $r $g $b
}

# ===================== MAGMA (5053-5057 -> block_54..58) =====================

# 54 BASALT COLUMNS — dark vertical bands
New-BlockFromFunc 54 {
    param($x, $y, $rng)
    $col = [math]::Floor($x / 8)
    $shade = (($col * 11) % 4) * 7
    $r = 52.0 + $shade; $g = 50.0 + $shade; $b = 54.0 + $shade
    if (($x % 8) -ge 7) { $r = 28; $g = 26; $b = 30 }
    if (($y + $col * 5) % 14 -lt 1) { $r -= 10; $g -= 10; $b -= 10 }
    C $r $g $b
}

# 55 LAVA CRACKS — dark rock with glowing web
New-BlockFromFunc 55 {
    param($x, $y, $rng)
    $r = 46.0; $g = 34.0; $b = 34.0
    $c1 = [math]::Abs(($y - 20) - [math]::Sin($x * 0.42) * 9)
    $c2 = [math]::Abs(($x - 20) - [math]::Sin($y * 0.38 + 2) * 10)
    $glow = [math]::Min($c1, $c2)
    if ($glow -lt 1.2) { $r = 255; $g = 190; $b = 40 }
    elseif ($glow -lt 2.6) { $r = 235; $g = 90; $b = 20 }
    elseif ($glow -lt 5) { $r = 120 - $glow * 8; $g = 50; $b = 30 }
    C $r $g $b
} $false

# 56 EMBER ROCK — dark with glowing embers
New-BlockFromFunc 56 {
    param($x, $y, $rng)
    $n = [math]::Sin($x * 0.7 + $y) * [math]::Sin($y * 0.6)
    $r = 58.0 + $n * 8; $g = 44.0 + $n * 6; $b = 42.0 + $n * 6
    foreach ($em in @(@(7, 9), @(22, 6), @(33, 15), @(12, 24), @(27, 30), @(6, 34), @(36, 33), @(18, 15))) {
        $d = [math]::Sqrt(($x - $em[0]) * ($x - $em[0]) + ($y - $em[1]) * ($y - $em[1]))
        if ($d -lt 1.4) { $r = 255; $g = 160; $b = 40 }
        elseif ($d -lt 3.2) { $r += (3.2 - $d) * 40; $g += (3.2 - $d) * 14 }
    }
    C $r $g $b
}

# 57 OBSIDIAN — near-black purple with glints
New-BlockFromFunc 57 {
    param($x, $y, $rng)
    $r = 24.0; $g = 14.0; $b = 34.0
    $g1 = [math]::Abs(($x + $y) - 26)
    $g2 = [math]::Abs(($x - $y) - 6)
    if ($g1 -lt 0.8) { $r = 130; $g = 100; $b = 180 }
    if ($g2 -lt 0.6) { $r = 96; $g = 70; $b = 140 }
    C $r $g $b
}

# 58 MAGMA FLOW — molten orange bands
New-BlockFromFunc 58 {
    param($x, $y, $rng)
    $w = [math]::Sin($x * 0.35 + $y * 0.18) * 5
    $band = ($y + $w + 40) % 14
    $r = 210.0; $g = 70.0; $b = 16.0
    if ($band -lt 4) { $r = 255; $g = 190; $b = 50 }
    elseif ($band -lt 6) { $r = 250; $g = 120; $b = 26 }
    elseif ($band -ge 12) { $r = 130; $g = 30; $b = 10 }
    C $r $g $b
} $false

# ===================== CURVES (5058-5067 -> block_59..68) =====================
# All horizontally SYMMETRIC (x mirrored around 19.5) so the curve mesh's
# alternating mirror-tiling joins with zero seams. Y = ribbon cross-section:
# bright core rows, darker edge rows = rounded-tube feel.

function Cyl([double]$y) { return 0.52 + 0.48 * [math]::Sin([math]::PI * $y / 39.0) }

function New-CurveBlock([int]$n, [scriptblock]$fn) {
    New-BlockFromFunc $n {
        param($x, $y, $rng)
        $sx = $x; if ($sx -ge 20) { $sx = 39 - $sx }
        & $fn $sx $y
    } $false
}

# 59 RAINBOW RIBBON — six bands + white top sheen
New-CurveBlock 59 {
    param($sx, $y)
    $bands = @(@(255, 70, 70), @(255, 160, 40), @(255, 230, 60), @(80, 220, 90), @(70, 150, 255), @(170, 90, 255))
    $bi = [math]::Floor($y / 6.67); if ($bi -gt 5) { $bi = 5 }
    $c = $bands[$bi]
    $m = 0.75 + 0.25 * (Cyl $y)
    if ($y -le 1) { return C 255 255 255 }
    C ($c[0] * $m) ($c[1] * $m) ($c[2] * $m)
}

# 60 NEON TUBE CYAN — dark shell, blazing core
New-CurveBlock 60 {
    param($sx, $y)
    $d = [math]::Abs($y - 19.5)
    if ($d -lt 3) { return C 235 255 255 }
    if ($d -lt 7) { return C 60 (230 - $d * 8) 255 }
    if ($d -lt 13) { return C 16 (110 - $d * 4) (160 - $d * 3) }
    $tick = if (($sx % 10) -lt 1 -and $d -lt 17) { 26 } else { 0 }
    C (6 + $tick) (26 + $tick * 2) (38 + $tick * 2)
}

# 61 NEON TUBE MAGENTA
New-CurveBlock 61 {
    param($sx, $y)
    $d = [math]::Abs($y - 19.5)
    if ($d -lt 3) { return C 255 240 255 }
    if ($d -lt 7) { return C 255 60 (230 - $d * 6) }
    if ($d -lt 13) { return C (150 - $d * 4) 18 (130 - $d * 3) }
    $tick = if (($sx % 10) -lt 1 -and $d -lt 17) { 26 } else { 0 }
    C (34 + $tick * 2) (8 + $tick) (30 + $tick * 2)
}

# 62 GOLD RAIL — royal metal with rivets
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

# 63 STEEL PIPE — brushed cylinder
New-CurveBlock 63 {
    param($sx, $y)
    $m = Cyl $y
    $v = 205 * $m
    if ($y -ge 5 -and $y -le 9) { $v = 235 }
    $seam = if ($sx -lt 1) { -40 } else { 0 }
    $brush = (($y * 3 + $sx) % 7) - 3
    C ($v + $seam + $brush) ($v + $seam + $brush + 4) ($v + $seam + $brush + 10)
}

# 64 CANDY RIBBON — barber stripes (symmetric) over a tube
New-CurveBlock 64 {
    param($sx, $y)
    $m = 0.72 + 0.28 * (Cyl $y)
    $stripe = [math]::Floor(($sx + 2) / 5) % 2
    if ($stripe -eq 0) { C (240 * $m) (60 * $m) (80 * $m) } else { C (255 * $m) (250 * $m) (250 * $m) }
}

# 65 LAVA FLOW RIBBON — crust edges, molten core
New-CurveBlock 65 {
    param($sx, $y)
    $d = [math]::Abs($y - 19.5)
    if ($d -gt 15) { return C 40 26 24 }
    if ($d -gt 11) { return C 110 40 20 }
    $core = [math]::Sin($sx * 0.5) * 3
    if ($d -lt (4 + $core)) { return C 255 (220 - $d * 10) 60 }
    C 245 (110 - $d * 4) 24
}

# 66 ICE RIBBON — glassy blue, white sheen
New-CurveBlock 66 {
    param($sx, $y)
    $m = Cyl $y
    $r = 170 * $m + 40; $g = 216 * $m + 30; $b = 250 * $m + 5
    if ($y -ge 3 -and $y -le 7) { $r = 240; $g = 250; $b = 255 }
    $sp = [math]::Sqrt(($sx - 13) * ($sx - 13) + ($y - 24) * ($y - 24))
    if ($sp -lt 1.2) { $r = 255; $g = 255; $b = 255 }
    C $r $g $b
}

# 67 JUNGLE VINE — braided greens with leaf nubs
New-CurveBlock 67 {
    param($sx, $y)
    $m = Cyl $y
    $braid = [math]::Sin(($y * 0.55) + ($sx * 0.5)) + [math]::Sin(($y * 0.55) - ($sx * 0.5))
    $r = 40 + $braid * 10; $g = 130 * $m + $braid * 16 + 20; $b = 30 + $braid * 6
    $ld = [math]::Sqrt(($sx - 6) * ($sx - 6) + ($y - 8) * ($y - 8))
    if ($ld -lt 3.2) { $r = 70; $g = 200; $b = 60 }
    C $r $g $b
}

# 68 STARLIGHT — deep indigo with symmetric sparkles
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

Write-Output "ALL PACKS DONE"
