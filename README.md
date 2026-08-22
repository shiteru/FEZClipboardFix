# FEZClipboardFix

幻想大陸（中国版FEZ）のチャットコピーで発生する、中国語の文字化けを修正する小さなPowerShellツールです。

## 使い方

1. `Start.cmd` をダブルクリックします。
2. 起動したPowerShell画面を開いたまま、幻想大陸をプレイします。
3. 幻想大陸のチャットをクリックしてコピーします。
4. 必要な場合は文字化けが自動的に修正されます。

幻想大陸からコピーした文章は、PowerShell画面にも順番に表示されます。
複数のチャットをコピーしてから、まとめて翻訳などに利用できます。

終了するときはPowerShell画面を閉じてください。

## 何が起きているのか

幻想大陸がコピーする中国語の元データは、簡体字中国語の **CP936（GBK系）** です。

ところが、クリップボードの言語情報 `CF_LOCALE` が日本語として設定されることがあります。
その場合、Windowsは元データを **CP932（Shift_JIS系）** として変換するため、中国語が文字化けします。

- **CP932** : 日本語 Windows で使われる文字コード（Shift_JIS系）
- **CP936** : 簡体字中国語 Windows で使われる文字コード（GBK系）

FEZClipboardFixは、コピー元が `FEzero_Client` であり、この誤変換が実際に起きている場合だけ、残っているCP936の元データから正しい中国語を復元してクリップボードへ戻します。

正常にコピーできている文章は変更しません。

## このツールがすること

- `FEzero_Client` からのクリップボード変更を確認します。
- CP932による誤変換が起きた場合だけ、CP936として正しい中国語を復元します。
- 幻想大陸からコピーした文章をPowerShell画面にも表示します。

## このツールがしないこと

- ゲームメモリの読み書き
- DLLの注入
- ゲームファイルの変更
- ネットワーク通信
- コピー履歴のファイル保存
- `FEzero_Client` 以外からコピーされた文章の変更

## Start.cmd について

ツール本体は `FEZClipboardFix.ps1` です。

`Start.cmd` はダブルクリックで起動しやすくするための補助ファイルです。
内容は次の1行だけで、PowerShellから本体を呼び出します。

```bat
@powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FEZClipboardFix.ps1"
```

`-ExecutionPolicy Bypass` は、この起動で作られたPowerShellプロセスにだけ適用されます。
Windows全体のExecution Policy設定を変更するものではありません。

## 対応環境

現在確認している対象は以下です。

- 幻想大陸 3.2版
- プロセス名 `FEzero_Client`
- Windows PowerShell
- Windowsの「Unicode対応ではないプログラムの言語（システム ロケール）」が「中国語（簡体字、中国）」の環境

## License

MIT License
