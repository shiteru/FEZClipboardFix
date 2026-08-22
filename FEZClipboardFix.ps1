# FEZClipboardFix
# 幻想大陸（中国版FEZ）のチャットコピーで発生する
# 中国語の文字化けを修正する小さなPowerShellツールです。
#
# CP932 = 日本語 Windows の文字コード（Shift_JIS 系）
# CP936 = 簡体字中国語 Windows の文字コード（GBK 系）

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms

# ============================================================
# 設定
# ============================================================

$TargetProcess = "FEzero_Client"

$cp932 = [Text.Encoding]::GetEncoding(932)
$cp936 = [Text.Encoding]::GetEncoding(936)


# ============================================================
# Windows API
#
# PowerShellからWindowsのクリップボードを直接調べるための部分です。
# ツール本体の考え方を追うだけなら、ここは読み飛ばして構いません。
# ============================================================

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ClipboardNative
{
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool OpenClipboard(IntPtr owner);

    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool CloseClipboard();

    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr GetClipboardData(uint format);

    [DllImport("user32.dll")]
    public static extern uint GetClipboardSequenceNumber();

    [DllImport("user32.dll")]
    public static extern IntPtr GetClipboardOwner();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(
        IntPtr window,
        out uint processId
    );

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr GlobalLock(IntPtr memory);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GlobalUnlock(IntPtr memory);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern UIntPtr GlobalSize(IntPtr memory);
}
"@


# ============================================================
# クリップボードの読み取り
# ============================================================

function Get-ClipboardOwnerProcess {
    $window = [ClipboardNative]::GetClipboardOwner()
    if ($window -eq [IntPtr]::Zero) {
        return $null
    }

    [uint32]$processId = 0
    [void][ClipboardNative]::GetWindowThreadProcessId(
        $window,
        [ref]$processId
    )

    if ($processId -eq 0) {
        return $null
    }

    try {
        return (Get-Process -Id $processId -ErrorAction Stop).ProcessName
    }
    catch {
        return $null
    }
}

function Get-MemoryBytes([IntPtr]$handle) {
    if ($handle -eq [IntPtr]::Zero) {
        return $null
    }

    $size = [uint64]([ClipboardNative]::GlobalSize($handle).ToUInt64())
    if ($size -eq 0 -or $size -gt [int]::MaxValue) {
        return $null
    }

    $pointer = [ClipboardNative]::GlobalLock($handle)
    if ($pointer -eq [IntPtr]::Zero) {
        return $null
    }

    try {
        $bytes = New-Object byte[] ([int]$size)
        [Runtime.InteropServices.Marshal]::Copy(
            $pointer,
            $bytes,
            0,
            [int]$size
        )
        return $bytes
    }
    finally {
        [void][ClipboardNative]::GlobalUnlock($handle)
    }
}

function Remove-NullTerminator([byte[]]$bytes) {
    if ($null -eq $bytes) {
        return $null
    }

    $length = 0
    while ($length -lt $bytes.Length -and $bytes[$length] -ne 0) {
        $length++
    }

    if ($length -eq 0) {
        return [byte[]]@()
    }

    $result = New-Object byte[] $length
    [Array]::Copy($bytes, $result, $length)
    return $result
}

function Get-ClipboardInfo {
    # ほかのアプリが一時的にクリップボードを使用している場合に備えて再試行します。
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        if ([ClipboardNative]::OpenClipboard([IntPtr]::Zero)) {
            try {
                # CF_TEXT (1)
                # 幻想大陸がコピーした元のバイト列を取得します。
                $textHandle = [ClipboardNative]::GetClipboardData(1)
                if ($textHandle -eq [IntPtr]::Zero) {
                    return $null
                }

                $raw = Remove-NullTerminator (Get-MemoryBytes $textHandle)
                if ($null -eq $raw -or $raw.Length -eq 0) {
                    return $null
                }

                # CF_UNICODETEXT (13)
                # Windowsが変換した現在のUnicode文字列を取得します。
                $unicode = $null
                $unicodeHandle = [ClipboardNative]::GetClipboardData(13)

                if ($unicodeHandle -ne [IntPtr]::Zero) {
                    $pointer = [ClipboardNative]::GlobalLock($unicodeHandle)

                    if ($pointer -ne [IntPtr]::Zero) {
                        try {
                            $unicode = [Runtime.InteropServices.Marshal]::PtrToStringUni(
                                $pointer
                            )
                        }
                        finally {
                            [void][ClipboardNative]::GlobalUnlock($unicodeHandle)
                        }
                    }
                }

                # CF_LOCALE (16)
                # WindowsがCF_TEXTを何語として扱ったか確認します。
                $codePage = $null
                $localeHandle = [ClipboardNative]::GetClipboardData(16)

                if ($localeHandle -ne [IntPtr]::Zero) {
                    $localeBytes = Get-MemoryBytes $localeHandle

                    if ($null -ne $localeBytes -and $localeBytes.Length -ge 4) {
                        $lcid = [BitConverter]::ToUInt32($localeBytes, 0)

                        try {
                            $culture = [Globalization.CultureInfo]::GetCultureInfo(
                                [int]$lcid
                            )
                            $codePage = $culture.TextInfo.ANSICodePage
                        }
                        catch {
                            $codePage = $null
                        }
                    }
                }

                return [PSCustomObject]@{
                    Raw      = $raw
                    Unicode  = $unicode
                    CodePage = $codePage
                }
            }
            finally {
                [void][ClipboardNative]::CloseClipboard()
            }
        }

        Start-Sleep -Milliseconds 20
    }

    throw "クリップボードを読み取れませんでした。"
}


# ============================================================
# 文字化けの判定と修正
# ============================================================

function Get-FEZText {
    $info = Get-ClipboardInfo
    if ($null -eq $info) {
        return $null
    }

    # 通常はWindowsが作ったUnicode文字列をそのまま使います。
    $text = $info.Unicode

    # 幻想大陸の中国語はCP936 (GBK系) のバイト列です。
    # CF_LOCALEが誤って日本語 CP932 になった場合だけ、
    # 元のバイト列をCP936として読み直します。
    if ($info.CodePage -eq 932) {
        $text932 = $cp932.GetString($info.Raw)
        $text936 = $cp936.GetString($info.Raw)

        # Windowsが実際にCP932として誤変換した場合だけ修正します。
        if ($info.Unicode -eq $text932 -and $text932 -ne $text936) {
            $text = $text936

            for ($attempt = 0; $attempt -lt 5; $attempt++) {
                try {
                    [System.Windows.Forms.Clipboard]::SetText(
                        $text,
                        [System.Windows.Forms.TextDataFormat]::UnicodeText
                    )
                    break
                }
                catch {
                    if ($attempt -eq 4) {
                        throw "修正した文章をクリップボードへ書き込めませんでした。"
                    }
                    Start-Sleep -Milliseconds 30
                }
            }
        }
    }

    return $text
}


# ============================================================
# メイン処理
# ============================================================

$lastSequence = [ClipboardNative]::GetClipboardSequenceNumber()

Write-Host ""
Write-Host "========================================"
Write-Host " FEZClipboardFix"
Write-Host "========================================"
Write-Host ""
Write-Host "幻想大陸のチャットコピーで発生する"
Write-Host "中国語の文字化けを修正します。"
Write-Host ""
Write-Host "この画面には、幻想大陸からコピーした文章が表示されます。"
Write-Host "画面を開いたままご利用ください。"
Write-Host ""
Write-Host "----------------------------------------"
Write-Host ""

while ($true) {
    try {
        Start-Sleep -Milliseconds 80

        $sequence = [ClipboardNative]::GetClipboardSequenceNumber()

        if ($sequence -eq 0 -or $sequence -eq $lastSequence) {
            continue
        }

        # 変更直後にコピー元を確認します。
        $ownerProcess = Get-ClipboardOwnerProcess
        $lastSequence = $sequence

        # 幻想大陸以外からのコピーには何もしません。
        if ($ownerProcess -ne $TargetProcess) {
            continue
        }

        # 幻想大陸がクリップボードへの書き込みを終えるまで少し待ちます。
        Start-Sleep -Milliseconds 40

        $text = $null

        # コピー直後のタイミング差に備えて短く再試行します。
        for ($retry = 0; $retry -lt 3 -and $null -eq $text; $retry++) {
            $text = Get-FEZText

            if ($null -eq $text) {
                Start-Sleep -Milliseconds 35
            }
        }

        if ($null -ne $text) {
            # 画面に表示する文章 = 最終的にコピーできた文章
            Write-Host $text

            # 自分自身がクリップボードを書き直した場合の変更通知を無視します。
            $lastSequence = [ClipboardNative]::GetClipboardSequenceNumber()
        }
    }
    catch {
        Write-Host ("Error: " + $_.Exception.Message) -ForegroundColor Red

        # エラー後も監視を続けます。
        Start-Sleep -Milliseconds 200
        $lastSequence = [ClipboardNative]::GetClipboardSequenceNumber()
    }
}
