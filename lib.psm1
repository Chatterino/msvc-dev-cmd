$ProgramFilesX86 = ${env:ProgramFiles(x86)}
$ProgramFilesList = @(
	${env:ProgramFiles(x86)}
	$env:ProgramFiles
)
$Editions = @(
	"Enterprise",
	"Professional",
	"Community",
	"BuildTools"
)
$Years = @(
	"2026",
	"2022",
	"2019",
	"2017"
)
$VsYearVersion = @{
	"2026" = "18.0"
    "2022" = "17.0"
    "2019" = "16.0"
    "2017" = "15.0"
    "2015" = "14.0"
    "2013" = "12.0"
}

$VsWherePath = Join-Path $ProgramFilesX86 "Microsoft Visual Studio\Installer"

function Convert-VsVersionToVersionNumber {
	param([string]$VsVersion)
	if ($VsYearVersion.Values -contains $VsVersion)
	{
		return $VsVersion
	}
	if ($VsYearVersion.ContainsKey($VsVersion))
	{
		return $VsYearVersion[$VsVersion]
	}
	return $VsVersion
}

function Convert-VsVersionToYear {
	param([string]$VsVersion)
	if ($VsYearVersion.ContainsKey($VsVersion))
	{
		return $VsVersion
	}
	foreach ($kv in $VsYearVersion.GetEnumerator())
	{
		if ($kv.Value -eq $VsVersion)
		{
			return $kv.Key
		}
	}
	return $VsVersion
}

function Find-WithVsWhere {
	param(
		[string]$Pattern,
		[string]$VersionPattern
	)
	try
	{
		$arguments = @(
			"-products"
			"*"
		)
		if ($VersionPattern -eq "-latest")
		{
			$arguments += "-latest"
		}
		elseif ($VersionPattern -match '^-version\s+"(.+)"$')
		{
			$arguments += @(
				"-version"
				$Matches[1]
			)
		}
		$arguments += @(
			"-prerelease"
			"-property"
			"installationPath"
		)
		$installationPath = (& vswhere @arguments).Trim()
		if ($installationPath)
		{
			return Join-Path $installationPath $Pattern
		}
	}
	catch {
		Write-Host "::warning::vswhere failed: $_"
	}
	return $null
}

function Find-VcVarsAll {
	param([string]$VsVersion)
	$VersionNumber = Convert-VSVersionToVersionNumber $VsVersion
	if ($VersionNumber) {
		$upper = ($VersionNumber.Split(".")[0]) + ".9"
		$versionPattern = "-version `"$VersionNumber,$upper`""
	}
	else
	{
		$versionPattern = "-latest"
	}
	$path = Find-WithVsWhere "VC\Auxiliary\Build\vcvarsall.bat" $versionPattern
	if ($path -and (Test-Path $path))
	{
		Write-Host "Found with vswhere: $path"
		return $path
	}
	Write-Host "Not found with vswhere"
	if ($VsVersion)
	{
		$SearchYears = @(Convert-VsVersionToYear $VsVersion)
	}
	else
	{
		$SearchYears = $Years
	}
	foreach ($pf in $ProgramFilesList)
	{
		foreach ($year in $SearchYears)
		{
			foreach ($edition in $Editions)
			{
				$path = Join-Path $pf "Microsoft Visual Studio\$year\$edition\VC\Auxiliary\Build\vcvarsall.bat"
				Write-Host "Trying standard location: $path"
				if (Test-Path $path)
				{
					Write-Host "Found standard location: $path"
					return $path
				}
			}
		}
	}
	Write-Host "Not found in standard locations"
	$path = Join-Path $ProgramFilesX86 "Microsoft Visual C++ Build Tools\vcbuildtools.bat"
	if (Test-Path $path)
	{
		Write-Host "Found VS2015: $path"
		return $path
	}
	Write-Host "Not found in VS 2015 location: $path"
	throw "Microsoft Visual Studio not found"
}

function Test-IsPathVariable {
	param([string]$Name)
	@(
		"PATH",
		"INCLUDE",
		"LIB",
		"LIBPATH"
	) -contains $Name.ToUpper()
}

function Get-FilteredPathValue {
	param([string]$PathValue)
	$seen = @{}
	$result = foreach ($p in $PathValue -split ';')
	{
		if (-not $seen.ContainsKey($p))
		{
			$seen[$p] = $true
			$p
		}
	}
	$result -join ';'
}

# See https://github.com/Chatterino/msvc-dev-cmd#inputs
function Initialize-MSVCDevCmd {
	param(
		[string]$Arch,
		[string]$Sdk,
		[string]$Toolset,
		[string]$Uwp,
		[string]$Spectre,
		[string]$VsVersion
	)
	if (-not $IsWindows)
	{
		Write-Host "This is not a Windows virtual environment, bye!"
		return
	}
	# Add standard location of "vswhere" to PATH, in case it's not there.
	$env:PATH += ";$VsWherePath"
	# There are all sorts of way the architectures are called. In addition to
	# values supported by Microsoft Visual C++, recognize some common aliases.
	$aliases = @{
		"win32"  = "x86"
		"win64"  = "x64"
		"x86_64" = "x64"
		"x86-64" = "x64"
	}
	# Ignore case when matching as that's what humans expect.
	$lower = $Arch.ToLower()
	if ($aliases.ContainsKey($lower))
	{
		$Arch = $aliases[$lower]
	}
	# Due to the way Microsoft Visual C++ is configured, we have to resort to the following hack:
	# Call the configuration batch file and then output *all* the environment variables.
	$args = @($Arch)
	if ($Uwp -eq "true")
	{
		$args += "uwp"
	}
	if ($Sdk)
	{
		$args += $Sdk
	}
	if ($Toolset)
	{
		$args += "-vcvars_ver=$Toolset"
	}
	if ($Spectre -eq "true")
	{
		$args += "-vcvars_spectre_libs=spectre"
	}
	$vcVars = '"' + (Find-VcVarsAll $VSVersion) + '" ' + ($args -join ' ')
	Write-Host "::debug::vcvars command-line: $vcVars"
	$cmd = "set && cls && $vcVars && cls && set"
	$output = cmd.exe /c $cmd
	$parts = $output -split "`f"
	$oldEnv = @{}
	# Convert old environment lines into a dictionary for easier lookup.
	foreach ($line in $parts[0] -split "`r?`n")
	{
		if ($line -match "=")
		{
			$n, $v = $line -split "=", 2
			$oldEnv[$n] = $v
		}
	}
	$vcVarsOutput = $parts[1] -split "`r?`n"
	# If vsvars.bat is given an incorrect command line, it will print out
	# an error and *still* exit successfully. Parse out errors from output
	# which don't look like environment variables, and fail if appropriate.
	$errors = $vcVarsOutput | Where-Object {
		$_ -match '^\[ERROR.*\]' -and
		$_ -notmatch 'Error in script usage'
	}
	if ($errors)
	{
		throw ($errors -join "`n")
	}
	# Now look at the new environment and export everything that changed.
	# These are the variables set by vsvars.bat. Also export everything
	# that was not there during the first sweep: those are new variables.
	Write-Host "::group::Environment variables"
	foreach ($line in $parts[2] -split "`r?`n")
	{
		# vsvars.bat likes to print some fluff at the beginning.
		if ($line -notmatch "=")
		{
			continue
		}
		$name, $value = $line -split "=", 2
		$old = $oldEnv[$name]
		# For new variables "old_value === undefined".
		# Skip lines that don't look like environment variables.
		if ($old -ne $value)
		{
			Write-Host "Setting $name"
			# Special case for a bunch of PATH-like variables: vcvarsall.bat
			# just prepends its stuff without checking if its already there.
			# This makes repeated invocations of this action fail after some
			# point, when the environment variable overflows. Avoid that.
			if (Test-IsPathVariable $name)
			{
				$value = Get-FilteredPathValue $value
			}
			Set-Item Env:$name -Value $value
			"$name=$value" >> $env:GITHUB_ENV
		}
	}
	Write-Host "::endgroup"
	Write-Host "Configured Developer Command Prompt"
}

Export-ModuleMember -Function `
    Convert-VsVersionToVersionNumber,
    Convert-VsVersionToYear,
    Find-WithVsWhere,
    Find-VcVarsAll,
    Initialize-MSVCDevCmd
