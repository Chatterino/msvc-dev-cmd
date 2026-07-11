#Requires -Version 5.1
<#
.SYNOPSIS
    GitHub Action to setup MSVC Developer Command Prompt.
.DESCRIPTION
    PowerShell port of the JavaScript GitHub Action that configures
    the MSVC Developer Command Prompt with specific architecture,
    SDK version, toolset, UWP, spectre mitigations, and VS version.
.NOTES
    Assumes a companion module 'lib.psm1' exposing 'Setup-MSVCDevCmd'.
#>

Import-Module -Name (Join-Path $PSScriptRoot 'lib.psm1') -Force -ErrorAction Stop

function Invoke-Main {
    [CmdletBinding()]
    param ()

    # GitHub Actions exposes step inputs as $env:INPUT_<NAME>
    $arch      = $env:INPUT_ARCH
    $sdk       = $env:INPUT_SDK
    $toolset   = $env:INPUT_TOOLSET
    $uwp       = $env:INPUT_UWP
    $spectre   = $env:INPUT_SPECTRE
    $vsversion = $env:INPUT_VSVERSION

    # Invoke the setup function with the read inputs
    Setup-MSVCDevCmd `
        -Arch      $arch `
        -Sdk       $sdk `
        -Toolset   $toolset `
        -Uwp       $uwp `
        -Spectre   $spectre `
        -VsVersion $vsversion
}

try {
    Invoke-Main
}
catch {
    # Equivalent of `core.setFailed` — emits a workflow-command
    # error annotation and exits with a non-zero status code.
    $msg = "Could not setup Developer Command Prompt: $($_.Exception.Message)"
    Write-Host "::error $msg"
    exit 1
}
