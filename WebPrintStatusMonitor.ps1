# config.jsonから設定を読み込みます
$config = Get-Content -Path "$($PSScriptRoot)\config.json" | ConvertFrom-Json

# 必要な変数を定義します
$Url = $config.Url 
$StatusDir = Join-Path $PSScriptRoot 'Status'
$StatusChanged = $false
$retryCount = 0 #再試行初期値
$retryLimit = $config.retryLimit  #再試行限界回数
$retryInterval = $config.retryInterval  #再試行間隔
$StatusChanged = $false #ステータス変更フラグ
$LogDir = Join-Path $PSScriptRoot 'logs' # ログフォルダのパスを定義
$LogFilePath = Join-Path $LogDir 'log.txt' # ログファイルのパスを定義
$prHost = $config.prHost #プライマリ・サーバ名
$prPort = $config.prPort #Port
$authMonitor = $config.prAuth #認証情報
$MaxErrorCount = 5 #通信エラー時再試行回数
$PendingAttempt = 0 #待ち行列通信エラー初期値
$WebPrintStatusAttempt = 0 #Webプリントステータス通信エラー初期値


# ログを記録する関数
function Write-Log($level, $message) {
    # タイムスタンプの取得
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # ログメッセージの作成
    $logMessage = "$timestamp - $level - $message"
    
    # ログファイルにメッセージを書き込む
    Add-Content -Path $LogFilePath -Value $logMessage

    # ログファイルサイズと世代の管理
    if ((Get-Item $LogFilePath).Length -gt 10MB) {
        for ($i = 9; $i -ge 0; $i--) {
            $old = "$LogDir\log$i.txt"
            if (Test-Path $old) {
                if ($i -eq 9) {
                    # 最古のログファイルを削除
                    Remove-Item -Path $old -ErrorAction SilentlyContinue
                } else {
                    # 古いログファイルの名前を変更
                    $new = "$LogDir\log$($i + 1).txt"
                    Rename-Item -Path $old -NewName $new -ErrorAction SilentlyContinue
                }
            }
        }
        # 現在のログファイルを新しい世代としてリネームし、新しいログファイルを作成
        Rename-Item -Path $LogFilePath -NewName "$LogDir\log0.txt" -ErrorAction SilentlyContinue
        New-Item -Path $LogFilePath -ItemType File -ErrorAction SilentlyContinue
    }
}

# メールを送信するための関数
function Send-Mail($subject, $body) {
    $smtpServer = $config.smtpServer
    $smtpPort = $config.smtpPort
    $smtpUser = $config.smtpUser
    $smtpPassword = $config.smtpPassword
    $fromAddress = $config.from
    $toAddresses = [string]::Join(',', $config.recipients)
        
    # 相対パスでPythonスクリプトを指定
    $scriptPath = $PSScriptRoot
    $pythonScriptPath = Join-Path -Path $scriptPath -ChildPath "sendemail.exe"

    try {
        # Pythonスクリプトを呼び出し
        $result = & $pythonScriptPath $smtpServer $smtpPort $fromAddress $toAddresses $subject $body
        Write $result
        if ($result -like "*successfully sent*") {
            Write-Log -level "INFO" -message "The email has been successfully sent."
        } else {
            Write-Log -level "ERROR" -message "The email could not be sent. Error: $result"
        }
    } catch {
        Write-Log -level "ERROR" -message "The email could not be sent. Exception: $_"
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
function get-StatusWebPrintStatus($prHost,$prPort,$authMonitor,$WebPrintStatusAttempt){
    $protocol = Set-MonitorPort $prPort
    $Url = "${protocol}://${prHost}:${prPort}/api/health/web-print/?${authMonitor}"
    $StatusFilePath = Join-Path $StatusDir "WSConnect.status"

    # 過去ステータスを取得（カウントを取得）
    $PreviousStatus = if (Test-Path $StatusFilePath) { Get-Content $StatusFilePath } else { "0" }
    $ErrorCount = [int]$PreviousStatus
    # URLからJSONデータを取得します
    try {
        $Response = Invoke-RestMethod -Uri $Url
        Write-Log -level "INFO" -message "Successfully connected to $Url."
        # カウントをリセットして保存
        Set-Content -Path $StatusFilePath -Value "0"
        if ($ErrorCount -ne 0){ 
            $Body = "SUCCESS:Connection to the PaperCut primary Server has been restored."
            $Subject = "SUCCESS:Connection to the PaperCut primary Server has been restored."
            Send-Mail -subject $Subject -body $Body
            Write-Log -level "INFO" -message "Unable to connect to $Url. Attempt $WebPrintStatusAttempt of $retryLimit"
        }
        return $Response
    } catch {
        $WebPrintStatusAttempt ++
        Write-Log -level "ERROR" -message "Unable to connect to $Url. Attempt $WebPrintStatusAttempt of $retryLimit"

        if ($WebPrintStatusAttempt -eq $retryLimit) {
            $ErrorCount++
            # カウントを保存
            Set-Content -Path $StatusFilePath -Value $ErrorCount
            Write-Log -level "ERROR" -message "Failed to connect after $retryLimit attempts. Incrementing error count to $ErrorCount."
        
            if ($ErrorCount -eq $MaxErrorCount) {
                Write-Log -level "ERROR" -message "Reached maximum error attempts ($MaxErrorCount). Executing error handler."
                if($ErrorCount -eq $MaxErrorCount){
                    $Body = $config.Body.errorServerConnectMessage
                    $Subject = $config.Subject.errorServerConnectMessage
                    Send-Mail -subject $Subject -body $Body
                }
            }
        }
    return $Response,$WebPrintStatusAttempt
    }
}

# Webプリントの待ち行列
function get-StatusWebPrintJobsPending($prHost, $prPort, $authMonitor, $PendingAttempt) {
    $protocol = Set-MonitorPort $prPort
    $Url = "${protocol}://${prHost}:${prPort}/api/health/?${authMonitor}"
    $StatusFilePath = Join-Path $StatusDir "JPConnect.status"

    # 過去ステータスを取得（カウントを取得）
    $PreviousStatus = if (Test-Path $StatusFilePath) { Get-Content $StatusFilePath } else { "0" }
    $ErrorCount = [int]$PreviousStatus

    try {
        $Response = Invoke-RestMethod -Uri $Url
        Write-Log -level "INFO" -message "Successfully connected to $Url."

        # カウントをリセットして保存
        Set-Content -Path $StatusFilePath -Value "0"
        return $Response,$PendingAttempt
    } catch {
        $PendingAttempt ++
        Write-Log -level "ERROR" -message "Unable to connect to $Url. Attempt $PendingAttempt of $retryLimit"
        
        if ($PendingAttempt -eq $retryLimit) {
            $ErrorCount++
            Set-Content -Path $StatusFilePath -Value $ErrorCount
            Write-Log -level "ERROR" -message "Failed to connect after $retryLimit attempts. Incrementing error count to $ErrorCount."

            if ($ErrorCount -eq $MaxErrorCount) {
                Write-Log -level "ERROR" -message "Reached maximum error attempts ($MaxErrorCount). Executing error handler."
                $Body = $config.Body.errorServerConnectMessage
                $Subject = $config.Subject.errorServerConnectMessage
                #Send-Mail -subject $Subject -body $Body
            }
            exit
        }
    return $Response,$PendingAttempt
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

# メイン処理
function Main {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir }
    if (-not (Test-Path $StatusDir)) { New-Item -ItemType Directory -Path $StatusDir }

    while ($retryCount -lt $retryLimit) {
        $Response = get-StatusWebPrintStatus $prHost $prPort $authMonitor $WebPrintStatusAttempt
        $Response2 = get-StatusWebPrintJobsPending $prHost $prPort $authMonitor $PendingAttempt
        Write-Log -level "INFO" -message "PendingJobs: $($Response2.webPrint.pendingJobs)."
        $WebPrintStatusAttempt = $Response[1]
        $PendingAttempt = $Response2[1]


        # 各サーバに対して処理を実施
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
            #空白.statusの削除
            Get-ChildItem -Path $StatusDir -Filter .status | Remove-Item -Force
        }
        Start-Sleep -Seconds $retryInterval
        $retryCount++
    }
}

# メイン処理の実行
Main