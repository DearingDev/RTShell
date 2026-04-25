#Requires -Module Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\RTShell\RTShell.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'Get-RTTicket — datetime UTC kind' {

    BeforeAll {
        InModuleScope RTShell {
            $script:fakeRaw = [PSCustomObject]@{
                id              = 42
                Subject         = 'Test ticket'
                Status          = 'open'
                Queue           = [PSCustomObject]@{ id = ''; _url = '' }
                Owner           = 'Nobody'
                Requestor       = @()
                Cc              = @()
                AdminCc         = @()
                Priority        = 0
                FinalPriority   = 0
                InitialPriority = 0
                TimeEstimated   = 0
                TimeWorked      = 0
                TimeLeft        = 0
                Created         = '2026-04-24 21:38:00'
                Starts          = '2026-04-24 00:00:00'
                Started         = '2026-04-24 00:00:00'
                Due             = '2026-04-30 00:00:00'
                Resolved        = '1970-01-01 00:00:00'
                LastUpdated     = '2026-04-24 21:40:00'
                CustomFields    = @()
            }

            Mock Invoke-RTRequest { $script:fakeRaw } -ParameterFilter { $Path -like 'ticket/*' }
        }

        $script:Ticket = Get-RTTicket -Id 42
    }

    It 'Created has DateTimeKind.Utc' {
        $script:Ticket.Created.Kind | Should -Be ([System.DateTimeKind]::Utc)
    }

    It 'LastUpdated has DateTimeKind.Utc' {
        $script:Ticket.LastUpdated.Kind | Should -Be ([System.DateTimeKind]::Utc)
    }

    It 'Resolved is null for epoch sentinel 1970-01-01' {
        $script:Ticket.Resolved | Should -BeNullOrEmpty
    }

    Context '-Detailed' {
        BeforeAll {
            $script:Detailed = Get-RTTicket -Id 42 -Detailed
        }

        It 'Created has DateTimeKind.Utc' {
            $script:Detailed.Created.Kind | Should -Be ([System.DateTimeKind]::Utc)
        }

        It 'LastUpdated has DateTimeKind.Utc' {
            $script:Detailed.LastUpdated.Kind | Should -Be ([System.DateTimeKind]::Utc)
        }

        It 'Starts has DateTimeKind.Utc' {
            $script:Detailed.Starts.Kind | Should -Be ([System.DateTimeKind]::Utc)
        }

        It 'Started has DateTimeKind.Utc' {
            $script:Detailed.Started.Kind | Should -Be ([System.DateTimeKind]::Utc)
        }

        It 'Due has DateTimeKind.Utc' {
            $script:Detailed.Due.Kind | Should -Be ([System.DateTimeKind]::Utc)
        }
    }
}
