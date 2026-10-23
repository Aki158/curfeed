# curfew

決めた時間帯以外は、SNS や YouTube などのサイトを見られなくする macOS 用のコマンドです。
たとえば「21:00〜22:00 だけ SNS を見てよい」という使い方を想定しています。

- 許可時間帯以外は、登録したドメインを `/etc/hosts` でブロックします
- ブロックが始まった時点で開いたままの Chrome のタブも自動で閉じ、Chrome に残っている接続を切ります
- 追加のアプリや有料サービスは不要です（macOS 標準の launchd と sh だけで動きます）

## 動作環境

- macOS（macOS 26 で確認）
- 管理者権限（インストールと設定の変更に必要）
- Google Chrome（開いたままのタブを閉じる機能のみ。他のブラウザでも hosts によるブロックは効きます）

## インストール

```sh
git clone <このリポジトリの URL> ~/workspace/curfew
cd ~/workspace/curfew
sudo ./install.sh
```

インストール中に「"sh"（または "osascript"）が "Google Chrome" を制御しようとしています」と表示されたら「OK」を押してください。
見逃した場合は、システム設定 → プライバシーとセキュリティ → オートメーション から後で許可できます。

また「バックグラウンド項目が追加されました」という通知が出ます。システム設定 → 一般 → ログイン項目と機能拡張 でオフにすると、自動切り替えが止まります。

### 最初の設定

インストール直後は、許可時間帯が 24 時間（00:00〜24:00）、ブロックするサイトは空の状態で、まだ何もブロックしません。
次の2つを決めると、許可時間帯以外にブロックが始まります。

1. ブロックしたいサイトのドメインを登録する（`www.` の有無は別のドメインとして扱うので、両方登録するのがおすすめです）
2. 見てもよい時間帯（許可時間帯）を決める

```sh
curfew add youtube.com www.youtube.com x.com www.instagram.com instagram.com
curfew set-time 21:00 22:00
```

あとで制限をやめたくなったら、`curfew set-time 00:00 24:00` で 24 時間許可に戻せます。

## 使い方

```sh
curfew                         # 今の状態（curfew status と同じ）
curfew list                    # ブロックするドメインの一覧
curfew add tiktok.com          # ドメインを追加（URL を貼り付けてもよい）
curfew remove tiktok.com       # ドメインを削除
curfew set-time 21:00 22:00    # 許可時間帯を変更（00:00 24:00 で 24 時間許可）
curfew log                     # 切り替えとタブを閉じた記録（curfew log 50 で件数指定）
curfew uninstall               # curfew を削除（確認あり。--yes で確認を省く）
curfew help                    # 使い方
```

`add` / `remove` / `set-time` / `uninstall` は管理者パスワードを求めます。`add` / `remove` / `set-time` の変更はすぐ hosts に反映されます。

`curfew status` の表示例:

```
状態: ブロック中
許可時間帯: 21:00〜22:00
次の解除: 21:00（あと2時間42分）
ブロック対象: 5 ドメイン
自動切り替え: 動作中
```

## 仕組み

| 役割 | 実体 | 動くタイミング |
|---|---|---|
| hosts の切り替え | `/usr/local/libexec/curfew/apply`（root の LaunchDaemon `local.curfew`） | 起動時と1分ごと |
| 開いたままのタブを閉じ、残っている接続を切る | `/usr/local/libexec/curfew/close-tabs`（ログイン中のユーザーの LaunchAgent `local.curfew.close-tabs`） | hosts が変わった直後と1分ごと |
| 操作 | `/usr/local/bin/curfew` | 手動 |

- hosts は `# >>> curfew >>>` 〜 `# <<< curfew <<<` の区間だけを書き換えます。それ以外の行には触れません。
- ブロック中かどうかは、タブを閉じる側も `/etc/hosts` のブロック区間で判断します。時刻の判定は `apply` だけが行います。

### hosts だけでは足りない理由

Chrome は一度つないだサーバーとの接続をしばらく使い回し、その間は接続先を DNS で調べ直しません。
そのため、許可時間中に YouTube などを開いていると、ブロックが始まってからも同じ接続でページを開けてしまいます。

curfew は次のタイミングで Chrome の通信プロセス（Network Service）を終了させ、残っている接続を切ります。
通信プロセスは Chrome がすぐに起動し直し、タブやウィンドウはそのまま残ります。

- ブロックが始まったとき
- ブロック中に、ブロック対象のタブを見つけて閉じたとき

## 設定ファイル

| ファイル | 内容 |
|---|---|
| `/usr/local/etc/curfew/config` | 許可時間帯（`curfew set-time` で変更） |
| `/usr/local/etc/curfew/blocklist` | ブロックするドメイン（`curfew add` / `remove` で変更） |

## アンインストール

```sh
curfew uninstall
```

リポジトリが手元にあれば、`sudo ./uninstall.sh`（または `make uninstall`）でも同じように削除できます。

プログラム本体・launchd のジョブ・hosts のブロック区間を取り除きます。

### アンインストール後に残るもの

入れ直したときに設定を引き継げるよう、次のファイルは残します。

| ファイル | 中身 |
|---|---|
| `/usr/local/etc/curfew/config` | 許可時間帯 |
| `/usr/local/etc/curfew/blocklist` | ブロックするドメインの一覧 |
| `/var/log/curfew.log` | 解除・ブロックの記録 |
| `/var/log/curfew-close-tabs.log` | タブを閉じた・接続を切った記録 |
| `/etc/hosts.before-curfew` | curfew を入れる前の hosts（元に戻すときの保険） |
| `~/Library/Application Support/curfew/` | タブを閉じる側が前回の状態を記録する場所 |

完全に消す場合は、アンインストールのあとに次を実行してください。
`/etc/hosts.before-curfew` を消すのは、`/etc/hosts` からブロック区間（`# >>> curfew >>>` で始まる部分）が消えていることを確かめてからにしてください。

```sh
sudo rm -rf /usr/local/etc/curfew /var/log/curfew.log /var/log/curfew-close-tabs.log /etc/hosts.before-curfew
rm -rf ~/"Library/Application Support/curfew"
```

ファイル以外に、Chrome を操作する許可も残ります。不要なら システム設定 → プライバシーとセキュリティ → オートメーション でオフにしてください。

## 制限事項

- 管理者権限があれば自分で解除できます。意志の力を補う「ひと手間」として使ってください。
- 開いたままのタブを閉じる機能と接続を切る機能は、Google Chrome だけに対応しています。
- 接続を切った瞬間に Chrome で行っていた通信（ダウンロードやビデオ通話など）は途切れます。
- `www.` の有無やサブドメインは別のドメインとして扱います（`youtube.com` と `www.youtube.com` は両方登録が必要です）。
- Chrome の「セキュア DNS」で独自の DNS プロバイダを指定していると、hosts が効かないことがあります。

## 開発

```sh
make test     # すべてのテストを実行（実際の /etc/hosts や Chrome には触れません）
```

テストは一時ディレクトリの hosts と設定を使い、Chrome の操作（`pgrep` / `pkill` / `osascript`）だけを差し替えて実行します。

## ライセンス

[MIT](LICENSE)
