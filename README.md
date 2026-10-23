# curfeed

決めた時間帯以外は、SNS や YouTube などのサイトを見られなくする macOS 用のコマンドです。
たとえば「21:00〜22:00 だけ SNS を見てよい」「昼休みと夜だけ見てよい」という使い方を想定しています。

名前は curfew（門限）と feed（SNS のタイムライン）を組み合わせた造語です。

- 許可時間帯以外は、登録したドメインを `/etc/hosts` でブロックします
- ブロックが始まった時点で開いたままの Chrome のタブも自動で閉じ、Chrome に残っている接続を切ります
- 追加のアプリや有料サービスは不要です（macOS 標準の launchd と sh だけで動きます）

## 動作環境

- macOS（macOS 26 で確認）
- 管理者権限（インストールと設定の変更に必要）
- Google Chrome（開いたままのタブを閉じる機能のみ。他のブラウザでも hosts によるブロックは効きます）

## インストール

```sh
git clone <このリポジトリの URL> ~/workspace/curfeed
cd ~/workspace/curfeed
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
curfeed add youtube.com www.youtube.com x.com www.instagram.com instagram.com
curfeed set-time 21:00-22:00
```

あとで制限をやめたくなったら、`curfeed set-time 00:00-24:00` で 24 時間許可に戻せます。

### 許可時間帯を複数にする

`set-time` に「開始-終了」を空白で区切って並べると、複数の許可時間帯を設定できます。

```sh
curfeed set-time 12:00-13:00 21:00-22:00   # 昼休みと夜の2つ
curfeed set-time 23:00-01:00               # 日付をまたぐ時間帯も使える
```

- `set-time` は、それまでの許可時間帯を**すべて置き換えます**（追加ではありません）。
- 重なったりつながったりしている時間帯は、自動で1つにまとめて保存します（例: `12:00-14:00 13:00-15:00` → `12:00〜15:00`）。
- 1つだけなら、`curfeed set-time 21:00 22:00` という書き方も使えます。

## 使い方

```sh
curfeed                         # 今の状態（curfeed status と同じ）
curfeed list                    # ブロックするドメインの一覧
curfeed add tiktok.com          # ドメインを追加（URL を貼り付けてもよい）
curfeed remove tiktok.com       # ドメインを削除
curfeed set-time 12:00-13:00 21:00-22:00   # 許可時間帯をまとめて置き換え（00:00-24:00 で 24 時間許可）
curfeed log                     # 切り替えとタブを閉じた記録（curfeed log 50 で件数指定）
curfeed uninstall               # curfeed を削除（確認あり。--purge で設定なども削除、--yes で確認を省く）
curfeed help                    # 使い方
```

`add` / `remove` / `set-time` / `uninstall` は管理者パスワードを求めます。`add` / `remove` / `set-time` の変更はすぐ hosts に反映されます。

`curfeed status` の表示例:

```
状態: ブロック中
許可時間帯: 12:00〜13:00, 21:00〜22:00
次の解除: 21:00（あと2時間42分）
ブロック対象: 5 ドメイン
自動切り替え: 動作中
```

## 仕組み

| 役割 | 実体 | 動くタイミング |
|---|---|---|
| hosts の切り替え | `/usr/local/libexec/curfeed/apply`（root の LaunchDaemon `local.curfeed`） | 起動時と1分ごと |
| 開いたままのタブを閉じ、残っている接続を切る | `/usr/local/libexec/curfeed/close-tabs`（ログイン中のユーザーの LaunchAgent `local.curfeed.close-tabs`） | hosts が変わった直後と1分ごと |
| 操作 | `/usr/local/bin/curfeed` | 手動 |

- hosts は `# >>> curfeed >>>` 〜 `# <<< curfeed <<<` の区間だけを書き換えます。それ以外の行には触れません。
- ブロック中かどうかは、タブを閉じる側も `/etc/hosts` のブロック区間で判断します。時刻の判定は `apply` だけが行います。

### hosts だけでは足りない理由

Chrome は一度つないだサーバーとの接続をしばらく使い回し、その間は接続先を DNS で調べ直しません。
そのため、許可時間中に YouTube などを開いていると、ブロックが始まってからも同じ接続でページを開けてしまいます。

curfeed は次のタイミングで Chrome の通信プロセス（Network Service）を終了させ、残っている接続を切ります。
通信プロセスは Chrome がすぐに起動し直し、タブやウィンドウはそのまま残ります。

- ブロックが始まったとき
- ブロック中に、ブロック対象のタブを見つけて閉じたとき

## 設定ファイル

| ファイル | 内容 |
|---|---|
| `/usr/local/etc/curfeed/config` | 許可時間帯（`curfeed set-time` で変更） |
| `/usr/local/etc/curfeed/blocklist` | ブロックするドメイン（`curfeed add` / `remove` で変更） |

## アンインストール

```sh
curfeed uninstall            # 設定などは残す（入れ直したときに引き継ぐ）
curfeed uninstall --purge    # 設定・ログなども含めてすべて削除する
```

リポジトリが手元にあれば、`sudo ./uninstall.sh`（`--purge` も使えます）や `make uninstall` でも同じように削除できます。

どちらも、プログラム本体・launchd のジョブ・hosts のブロック区間を取り除きます。

### アンインストール後に残るもの

`--purge` を付けなかった場合は、入れ直したときに設定を引き継げるよう、次のファイルを残します。
アンインストールの最後に、残したものをすべて消すコマンドが表示されるので、あとから消したくなったらそれを実行してください。

| ファイル | 中身 |
|---|---|
| `/usr/local/etc/curfeed/config` | 許可時間帯 |
| `/usr/local/etc/curfeed/blocklist` | ブロックするドメインの一覧 |
| `/var/log/curfeed.log` | 解除・ブロックの記録 |
| `/var/log/curfeed-close-tabs.log` | タブを閉じた・接続を切った記録 |
| `/etc/hosts.before-curfeed` | curfeed を入れる前の hosts（元に戻すときの保険） |
| `~/Library/Application Support/curfeed/` | タブを閉じる側が前回の状態を記録する場所 |

表示されたコマンドを見逃した場合は、次のコマンドで同じように消せます。

```sh
sudo rm -rf /usr/local/etc/curfeed /var/log/curfeed.log /var/log/curfeed-close-tabs.log /etc/hosts.before-curfeed
rm -rf ~/"Library/Application Support/curfeed"
```

ファイル以外に、Chrome を操作する許可も残ります（`--purge` でも消えません）。不要なら システム設定 → プライバシーとセキュリティ → オートメーション でオフにしてください。

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
