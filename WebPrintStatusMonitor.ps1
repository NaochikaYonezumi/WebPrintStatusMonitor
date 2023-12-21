# config.jsonから設定を読み込みます
$config = Get-Content -Path "$($PSScriptRoot)\config.json" | ConvertFrom-Json

# 必要な変数を定義します
$Url = $config.Url 
$StatusDir = Join-Path $PSScriptRoot 'Status'
$StatusChanged = $false
$retryCount = 0 #再試行初期値
$retryLimit = $config.retryLimit  #再試行限界回数
$retryInterval = $config.retryInterval  #再試行間隔
$StatusChanged = $false　#ステータス変更フラグ
$LogDir = Join-Path $PSScriptRoot 'logs'　# ログフォルダのパスを定義
$LogFilePath = Join-Path $LogDir 'log.txt' # ログファイルのパスを定義
$prHost = $config.prHost #プライマリ・サーバ名
$prPort = $config.prPort #Port
$authMonitor = $config.prAuth

# ログを記録する関数
function Write-Log($level, $message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $level - $message"
    Add-Content -Path $LogFilePath -Value $logMessage

    # ログファイルサイズと世代の管理
    if ((Get-Item $LogFilePath).Length -gt 10MB) {
        1..9 | ForEach-Object {
            $old = 10 - $_
            $new = 9 - $_
            Rename-Item -Path "$LogDir\log$old.txt" -NewName "log$new.txt" -ErrorAction SilentlyContinue
        }
        Rename-Item -Path $LogFilePath -NewName "$LogDir\log9.txt" -ErrorAction SilentlyContinue
        Remove-Item -Path "$LogDir\log0.txt" -ErrorAction SilentlyContinue
    }
}


# メールを送信するための関数
function Send-Mail($subject, $body) {
    $smtpServer = $config.smtpServer
    $smtpPort = $config.smtpPort
    $message = New-Object System.Net.Mail.MailMessage
    $message.From = $config.from
    $message.Subject = $subject
    $message.Body = $body

    foreach ($recipient in $config.recipients) {
        $message.To.Add($recipient)
    }

    # SMTP クライアントオブジェクトの作成
    $smtpClient = New-Object System.Net.Mail.SmtpClient($smtpServer, $smtpPort)

    # メール送信
    try {
        $smtpClient.Send($message)
        Write-Log -level "INFO" -message "The email has been successfully sent."
    } catch {
        Write-Log -level "ERROR" -message "The email could not be sent."
    }
}


#プロトコル設定関数
function Set-MonitorPort($prPort){
    if(($prPort -eq 9191) -or ($prPort -eq 80)){
        return "http"
    } elseif (($prPort -eq 9192) -or ($prPort -eq 443)){
            return "https"
    } else{
        Write-Output "予期せぬポート番号です。ポート番号を見直してください。"
        Write-Log -level "ERROR" -message "Unable to connect to $Url."
        exit
    }
}

# Webプリントのステータス取得関数
function get-StatusWebPrintStatus($prHost,$prPort,$authMonitor){
    $protocol = Set-MonitorPort $prPort
    $Url = "${protocol}://${prHost}:${prPort}/api/health/web-print/?${authMonitor}"
    # URLからJSONデータを取得します
    try {
        $Response = Invoke-RestMethod -Uri $Url
        Write-Log -level "INFO" -message "Successfully connected to $Url."
        return $Response
    } catch {
        Write-Log -level "ERROR" -message "Unable to connect to $Url."
        $Body = $config.Body.errorServerConnectMessage
        $Subject = $config.Subject.errorServerConnectMessage
        Send-Mail -subject $Subject -body $Body
        Write-Log -level "INFO" -message "Mail sent with subject: $Subject."
        exit
    }
}

# Webプリントの待ち行列
function get-StatusWebPrintJobsPending($prHost,$prPort,$authMonitor){
    $protocol = Set-MonitorPort $prPort
    $Url = "${protocol}://${prHost}:${prPort}/api/health/?${authMonitor}"
    # URLからJSONデータを取得します
    try {
        $Response = Invoke-RestMethod -Uri $Url
        Write-Log -level "INFO" -message "Successfully connected to $Url."
        return $Response
    } catch {
        Write-Log -level "ERROR" -message "Unable to connect to $Url."
        $Body = $config.Body.errorServerConnectMessage
        $Subject = $config.Subject.errorServerConnectMessage
        Send-Mail -subject $Subject -body $Body
        Write-Log -level "INFO" -message "Mail sent with subject: $Subject."
        exit
    }
}

# ステータス確認関数
function CheckStatusChange ($CurrentStatus, $PreviousStatus, $ServerHost, $config) {
    if (($CurrentStatus -ne $PreviousStatus) -and ($PreviousStatus -ne $null)){
        $Body = $config.Body.$CurrentStatus -f $ServerHost
        $Subject = $config.Subject.$CurrentStatus -f $ServerHost
        Write-Log -level "INFO" -message "Mail sent with subject: $Subject."
        Write-Output "Mail sent with subject: $Subject."
        Send-Mail -subject $Subject -body $Body
    }
}

# main
#　各フォルダがない場合は作成
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir }
if (-not (Test-Path $StatusDir)) { New-Item -ItemType Directory -Path $StatusDir }

while ($retryCount -lt $retryLimit) {
    $Response = get-StatusWebPrintStatus $prHost $prPort $authMonitor
    $Response2 = get-StatusWebPrintJobsPending $prHost $prPort $authMonitor
    Write-Log -level "INFO" -message "PendingJobs: $($Response2.webPrint.pendingJobs)."
    Write-Output "PendingJobs: $($Response2.webPrint.pendingJobs)"

    #各サーバに対して処理を実施
    $Response.servers | ForEach-Object {
        $ServerHost = $_.host
        $Status = $_.status
        Write-Log -level "INFO" -message "ServerName: ${ServerHost} Status: ${Status}."
        Write-Output "ServerName: ${ServerHost} Status: ${Status}."
        $StatusFilePath = Join-Path $StatusDir "$ServerHost.status"
        #過去ステータス
        $PreviousStatus = if (Test-Path $StatusFilePath) { Get-Content $StatusFilePath } else { $null }
        Write-Output "ServerName: ${ServerHost} PreviousStatus: ${PreviousStatus}."
        #現在のステータスを書き込む
        Set-Content -Path $StatusFilePath -Value $Status
        # ステータス確認関数の呼び出し
        CheckStatusChange $Status $PreviousStatus $ServerHost $config
    }
    Start-Sleep -Seconds $retryInterval
    $retryCount++
}
