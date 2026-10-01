param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$sourcePath = Join-Path $projectPath 'assets/branding/dearshelf-pumpkin-cat.png'
$foregroundPath = Join-Path $projectPath 'assets/branding/dearshelf-pumpkin-cat-foreground.png'
$resourcePath = Join-Path $projectPath 'android/app/src/main/res'
$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
$foreground = [System.Drawing.Bitmap]::FromFile($foregroundPath)

function Export-IconBitmap {
    param(
        [System.Drawing.Image]$Image,
        [int]$CanvasSize,
        [int]$ArtSize,
        [string]$OutputPath
    )

    $bitmap = [System.Drawing.Bitmap]::new(
        $CanvasSize, $CanvasSize,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $offset = [int][Math]::Round(($CanvasSize - $ArtSize) / 2)
        $destination = [System.Drawing.Rectangle]::new($offset, $offset, $ArtSize, $ArtSize)
        $graphics.DrawImage(
            $Image, $destination, 0, 0, $Image.Width, $Image.Height,
            [System.Drawing.GraphicsUnit]::Pixel, $attributes
        )
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $attributes.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    if ($foreground.GetPixel(0, 0).A -ne 0) {
        throw 'The adaptive foreground must have a transparent background.'
    }
    $densities = [ordered]@{
        mdpi = 1.0
        hdpi = 1.5
        xhdpi = 2.0
        xxhdpi = 3.0
        xxxhdpi = 4.0
    }
    foreach ($entry in $densities.GetEnumerator()) {
        $targetDirectory = Join-Path $resourcePath ('mipmap-' + $entry.Key)
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        $legacySize = [int][Math]::Round(48 * $entry.Value)
        Export-IconBitmap -Image $source -CanvasSize $legacySize -ArtSize $legacySize `
            -OutputPath (Join-Path $targetDirectory 'ic_launcher.png')

        # Android layers are 108 dp; keep the entire foreground within the central 66 dp.
        $adaptiveSize = [int][Math]::Round(108 * $entry.Value)
        $artSize = [int][Math]::Round(66 * $entry.Value)
        Export-IconBitmap -Image $foreground -CanvasSize $adaptiveSize -ArtSize $artSize `
            -OutputPath (Join-Path $targetDirectory 'ic_launcher_foreground.png')
        Write-Output ('Exported ' + $entry.Key + ': legacy ' + $legacySize + ' px, adaptive ' + $adaptiveSize + ' px')
    }
}
finally {
    $source.Dispose()
    $foreground.Dispose()
}
