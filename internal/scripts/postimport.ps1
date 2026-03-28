# Place all code that should be run after functions are imported here
Register-ArgumentCompleter -CommandName 'Add-RTTicketReply', 'Add-RTTicketComment', 'Resolve-RTTemplate' `
    -ParameterName 'TemplateName' `
    -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $templateDir = Join-Path ([System.Environment]::GetFolderPath('UserProfile')) '.rtshell' 'templates'
        if (Test-Path $templateDir) {
            Get-ChildItem -Path $templateDir -Filter '*.json' |
                ForEach-Object { $_.BaseName } |
                Where-Object   { $_ -like "$wordToComplete*" } |
                ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
        }
    }

Register-ArgumentCompleter -CommandName 'Search-RTTicket', 'New-RTTicket', 'Set-RTTicketQueue', 'Get-RTQueue' `
    -ParameterName 'Queue' `
    -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $configPath = Join-Path ([System.Environment]::GetFolderPath('UserProfile')) '.rtshell' 'config.json'
        if (Test-Path $configPath) {
            $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            if ($config -and $config.QueueCache) {
                @($config.QueueCache) |
                    Where-Object   { $_.Name -like "$wordToComplete*" -and [int]$_.Disabled -eq 0 } |
                    ForEach-Object {
                        $tooltip = if ($_.Description) { "$($_.Name) — $($_.Description)" } else { $_.Name }
                        [System.Management.Automation.CompletionResult]::new(
                            "'$($_.Name)'",
                            $_.Name,
                            'ParameterValue',
                            $tooltip
                        )
                    }
            }
        }
    }