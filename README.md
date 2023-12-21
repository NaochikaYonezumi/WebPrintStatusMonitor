# 概要
  - Papercutのシステム・ヘルス・モニタリングを監視し、Webプリントのステータスが変わると通知するスクリプトです。
    - Webプリントが以下のステータスになったとき、自動的に通知されます。<br>
      ※ステータスが変わった瞬間通知は送信されますが、同じステータスが検出された場合、通知は行われません。
      - OK:Webプリントが正常に立ち上がった際に通知されます。
      - ERROR:WebPrintのアプリケーションが停止した場合に通知されます。
      - STOPPED:手動でWebプリントを停止した場合に通知されます。
# 設定方法
  設定は基本的にconfig.jsonファイルにて編集します。
  WebPrintStatusMonitorを任意のディレクトリに配置し、メモ帳などで編集するようにしてください。
## config.jsonの編集

```
{
    "prHost": "********", //プライマリ・サーバのホスト名、もしくはIP
    "prPort": "9191",//プライマリ・サーバのポート番号(http:9191)、(https:9192)
    "prAuth": "Authorization=******", //システム・ヘルス・モニタリングの値
    "smtpServer": "******", //smtpServerのホスト名
    "smtpPort": "25", //smtpのポート番号
    "from": "****@*****", //メールの送信元
    "recipients": [
        "*****@****", //メールの送信先
        "****@****"
    ],
    "Subject": {
        "STOPPED": "WARM: WebPrintServer: {0} has been stopped.", //Webプリントを手動停止した場合に送信するメールの件名
        "OK": "SUCCESS: WebPrintServer: {0} has been started.", //Webプリントが立ち上がった場合に送信するメールの件名
        "ERROR": "ERROR: WebPrintServer: {0} has encountered an error.", //Webプリントがエラーになったときのメールの件名
        "errorServerConnectMessage": "ERROR: The script could not connect to the primary server. Status could not be retrieved." //スクリプトがシステム・ヘルスモニタリングとの通信に失敗したときのメールの件名
    },
    "Body": {
        "STOPPED": "WARM: WebPrintServer: {0} has been stopped.", //Webプリントを手動停止した場合に送信するメールの本文
        "OK": "SUCCESS: WebPrintServer: {0} has been started.", //Webプリントが立ち上がった場合に送信するメールの本文
        "ERROR": "ERROR: WebPrintServer: {0} has encountered an error.", //Webプリントがエラーになったときのメールの本文
        "errorServerConnectMessage": "ERROR: The script could not connect to the primary server. Status could not be retrieved.\r\nPlease verify if the values in config.json are correct." //スクリプトがシステム・ヘルスモニタリングとの通信に失敗したときのメールの本文
    },
    "retryLimit": 6, //リトライ回数
    "retryInterval": 10  //リトライまでの時間
}
```
##システム・ヘルス・モニタリングの確認方法
  システム・ヘルス・モニタリングは下記方法でご確認ください。
  1. PaperCut管理者Web画面にログインします。
  2. <オプション>タブをクリックします。
  3. <拡張>タブをクリックします。
  4. [システム・ヘルス・モニタリング]欄にあるGETクエリ・パラメータから"&"より後の値を取得します。

     例)
     ```
     値: https://192.168.101.202:443/api/health/application-server/status?disk-threshold-mb=1&Authorization=qb6r8bDtHkop57a3c78suc2B4utH7sBn
     取得する値:Authorization=qb6r8bDtHkop57a3c78suc2B4utH7sBn
     ```
     
## タスクスケジューラへの登録
  WebPrintStatusMonitorは「StartUpWebPrintStatusMonitor.vbs」をタスクスケジューラに登録することで定期的にステータスを監視することが可能です。<br>
  タスクスケジューラの登録は下記方法で実施します。

  1. タスクスケジューラを開きます。
  2. [タスクスケジューラ] - [タスクスケジューラライブラリ]の順番に開きます。
  3. 画面右にある[タスクの作成]をクリックします。
  4. 「タスクの作成」ウィンドウが開きます。<全般>を以下のように設定します。

     ```
     名前:任意の名前
     説明:任意の説明
     タスクの実行時に使うユーザアカウント:管理者権限を持つアカウント
     ユーザがログインしているかどうかにかかわらず実行する。
     最上位の特権で実行する:有効化
     ```
     
  5.  <トリガー>タブをクリックし、[新規]ボタンをクリックし、以下のように設定します。
     
     ```
    設定:1回
    開始:任意の日時
    詳細設定:
      ・繰り返し間隔:1分間(任意の時間間隔)
      ・継続時間:無期限
     ```
     
  7. ページ下部にある[OK]ボタンをクリックします。
  8. <操作>タブをクリックします。ページ下部にある[新規]ボタンをクリックします。
  9. 「新しい操作」ウィンドウが表示されます。以下のように設定します。
     ```
     操作:プログラムの開始
     プログラム/スクリプト:[App_Path]\WebPrintStatusMonitor\StartUpWebPrintStatusMonitor.vbs
     引数:なし
     開始(オプション):[App_Path]\WebPrintStatusMonitor\
     ```
  10. ページ下部にある[OK]ボタンをクリックします。
  11. <条件>タブをクリックします。以下のように設定します。
      ```
      電源:
        - コンピュータをAC電源で使用している場合のみタスクを開始する。:無効化
      ```
  12. <設定>タブをクリックします。以下のように設定します。
      ```
        - タスクを停止するまでの時間:無効化
      ```
  13. ページ下部にある[OK]ボタンをクリックします。
