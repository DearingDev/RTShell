#Requires -Module Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\RTShell\RTShell.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Search-RTTicket — datetime UTC kind' {

    BeforeAll {
        InModuleScope RTShell {
            $script:fakeResponse = [PSCustomObject]@{
                total = 1
                page  = 1
                items = @(
                    [PSCustomObject]@{
                        id          = 99
                        Subject     = 'Test search ticket'
                        Status      = 'open'
                        Queue       = [PSCustomObject]@{ Name = 'General'; id = '' }
                        Owner       = [PSCustomObject]@{ id = 'Nobody' }
                        Created     = '2026-04-24 21:38:00'
                        LastUpdated = '2026-04-24 21:40:00'
                    }
                )
            }

            Mock Invoke-RTRequest { $script:fakeResponse } -ParameterFilter { $Path -eq 'tickets' }
        }

        $script:Result = Search-RTTicket -Query 'id=99' | Select-Object -First 1
    }

    It 'Created has DateTimeKind.Utc' {
        $script:Result.Created.Kind | Should -Be ([System.DateTimeKind]::Utc)
    }

    It 'LastUpdated has DateTimeKind.Utc' {
        $script:Result.LastUpdated.Kind | Should -Be ([System.DateTimeKind]::Utc)
    }
}
