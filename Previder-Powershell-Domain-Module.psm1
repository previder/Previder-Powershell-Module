#
# Module 'Previder-Powershell-Module'
#

$Annexus = @{
    BaseUri = "https://portal.previder.nl";
    Uri = "https://portal.previder.nl/api";
    Headers = @{ };
    LastResponseHeaders = @{ };
    WaitForRateLimitReset = $true;
    RateLimitWaitThreshold = 100;
}

function New-AnnexusWebRequest
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $TRUE)]
        [string] $Uri,
        [string] $RequestMethod = "GET",
        $Body
    )

    $DefaultRequestMethod = "application/json"

    if ($Annexus.LastResponseHeaders -and $Annexus.LastResponseHeaders['X-Rate-Limit-Remaining'] -and $Annexus['WaitForRateLimitReset'])
    {
        $RateLimitRequestsRemaining = $Annexus.LastResponseHeaders['X-Rate-Limit-Remaining'] -as [int]
        $RateLimitResetTimeUnix = $Annexus.LastResponseHeaders['X-Rate-Limit-Reset'] -As [int]

        if ($null -ne $RateLimitRequestsRemaining -and $null -ne $RateLimitResetTimeUnix)
        {
            $RateLimitResetTime = (Get-Date "01.01.1970").AddSeconds($RateLimitResetTimeUnix)
            $RateLimitResetTime = $RateLimitResetTime.AddSeconds((get-timezone).GetUtcOffset($RateLimitResetTime).TotalSeconds)

            $RateLimitSecondsUntilReset = (New-TimeSpan -Start (get-date) -End $RateLimitResetTime).TotalSeconds

            if ([int]$RateLimitRequestsRemaining -lt $Annexus['RateLimitWaitThreshold'])
            {
                write-warning "Waiting for rate limit expiry. Requests remaining: $RateLimitRequestsRemaining. Time remaining $RateLimitSecondsUntilReset seconds"
                Start-Sleep -Seconds ($RateLimitSecondsUntilReset + 10)
            }
        }
    }

    if ($Body)
    {
        $Res = Invoke-WebRequest -WebSession $Annexus.Session -Headers $Annexus.Headers -Method $RequestMethod -Uri $Uri -ContentType $DefaultRequestMethod -Body $Body
    }
    else
    {
        $Res = Invoke-WebRequest -WebSession $Annexus.Session -Headers $Annexus.Headers -Method $RequestMethod -Uri $Uri -ContentType $DefaultRequestMethod
    }


    $Annexus.LastResponseHeaders = $Res.Headers

    if ($Res.Content)
    {
        return $( $Res.Content | convertfrom-json )
    }

}

function Connect-Annexus
{
    [CmdletBinding(DefaultParameterSetName = "credSet")]
    param(
        [parameter(ParameterSetName = "tokenSet", Mandatory = $TRUE)]
        [string] $Token,
        [parameter(ParameterSetName = "credSet", Mandatory = $TRUE)]
        [string] $Accountname,
        [parameter(ParameterSetName = "credSet", Mandatory = $TRUE)]
        [string] $Username,
        [parameter(ParameterSetName = "credSet", Mandatory = $TRUE)]
        [Security.SecureString] $Password,
        [parameter(ParameterSetName = "credSet", Mandatory = $FALSE)]
        [string] $OTP,
        [switch] $UseOTP,
        [string] $Uri
    )

    If ($UseOTP -and !$OTP)
    {
        $OTP = Read-Host 'OTP'
    }

    If ($Uri)
    {
        $Annexus.Uri = $Uri
    }

    If ($Token)
    {
        $Annexus.Headers.Add("X-Auth-Token", $Token)
    }
    Else
    {

        $UnmanagedString = [System.IntPtr]::Zero
        try
        {
            $UnmanagedString = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Password);
            $UnsecurePassword = [Runtime.InteropServices.Marshal]::PtrToStringUni($UnmanagedString);
        }
        finally
        {
            [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($UnmanagedString);
        }

        $Credentials = @{
            "username" = "$( $Username )@$( $Accountname )";
            "password" = $UnsecurePassword;
            "otp" = $OTP;
        }

        $Res = Invoke-WebRequest -SessionVariable AnnexusSession -Method GET -Uri "$( $Annexus.Uri )/" -ContentType "application/json"

        $Annexus.Session = $AnnexusSession
        $Annexus.Session.Headers.Add("X-CSRF-Token", $Res.Headers["X-CSRF-Token"])

        try
        {
            $Res = Invoke-WebRequest -WebSession $Annexus.Session -Method POST -Uri "$( $Annexus.BaseUri )/logincheck" -Body $Credentials -ContentType "application/x-www-form-urlencoded"
        }
        catch
        {
            Write-Host "Error logging in"
            return
        }

        $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/core/session"
        $Annexus.Session.Headers.Set_Item("X-CSRF-Token", $Res.Headers["X-CSRF-Token"])

        Write-Host "Logged in successfully"
        $Res
    }
}

Function Set-AnnexusRateLimitHandling
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Boolean]$WaitForRateLimitReset = $null,
        [Parameter(Mandatory = $false)]
        [int]$RateLimitWaitThreshold = $null
    )
    if ($WaitForRateLimitReset -ne $null)
    {
        $Annexus['WaitForRateLimitReset'] = $WaitForRateLimitReset
    }

    if ($RateLimitWaitThreshold -ne $null)
    {
        $Annexus['RateLimitWaitThreshold'] = $RateLimitWaitThreshold
    }
}

function Set-HandleByCustomer
{
    [CmdletBinding()]
    param(
        [string] $Id
    )

    if ( $Annexus.Headers.ContainsKey("X-CustomerId"))
    {
        Write-Host "Clearing handle by customer"
        $Annexus.Headers.Remove("X-CustomerId")
    }

    if ($Id)
    {
        $Customer = Get-Customer -Id $Id
        Write-Host "Handle by customer $( $Customer.name )"
        $Annexus.Headers.Add("X-CustomerId", $Customer.id)
    }
}

function RegisterDomain
{
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $TRUE)]
        [string] $DomainName,
        [parameter(Mandatory = $TRUE)]
        [string] $Registrant,
        [string] $AdministrativeContact,
        [string] $TechnicalContact,
    	[string] $TransferToken)

    $checkContact = GetDomainContact -Query $Registrant
    if ($checkContact.totalElements -eq 0)
    {
        throw "Registrant not found"
    }



    if (!$AdministrativeContact)
    {
        $AdministrativeContact = $Registrant
    }
    else
    {
        $checkContact = GetDomainContact -Query $AdministrativeContact
        if ($checkContact.totalElements -eq 0)
        {
            throw "Administrative contact not found"
        }

    }
    if (!$TechnicalContact)
    {
        $TechnicalContact = $Registrant
    }
    else
    {
        $checkContact = GetDomainContact -Query $TechnicalContact
        if ($checkContact.totalElements -eq 0)
        {
            throw "Technical contact not found"
        }
    }

    $meta = GetTldProperties -DomainName $DomainName -Registrant $Registrant -AdministrativeContact $AdministrativeContact -TechnicalContact  $TechnicalContact

    if (-not ([string]$meta -eq {}))
    {
        throw "Cannot register domain $DomainName because it requires metadata. You can fix this by registering a single domain with the tld in the previder portal and saving the metadata in the given domain contacts."

    }

    $domainRegister = @{
        domainName = $DomainName
        registrant = $Registrant
        techContact = $TechnicalContact
        adminContact = $AdministrativeContact
        transferTokenIn = $TransferToken
        
    }


    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/drs/domain" -RequestMethod POST -Body (ConvertTo-Json -Depth 10 @($domainRegister))
    $Res
}





function GetDomainContact
{

    [CmdletBinding()]
    param(
        [Int16] $Page = 0,
        [Int16] $Size = 10,
        [string] $Query = "",
        [string] $Sort = "name,asc"
    )

    $QueryParams = @{
        "page" = $Page
        "size" = $Size
        "query" = $Query
        "sort" = $Sort
    }

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/drs/contact" -Body $QueryParams
    $Res

}

function GetTldProperties
{
    [CmdletBinding(DefaultParameterSetName = "domainNameSet")]
    param(
        [parameter(Mandatory = $TRUE)]
        [string] $DomainName,
        [parameter(Mandatory = $TRUE)]
        [string] $Registrant,
        [parameter(Mandatory = $TRUE)]
        [string] $AdministrativeContact,
        [parameter(Mandatory = $TRUE)]
        [string] $TechnicalContact

    )




    $tldSplit = $DomainName.split(".")

    $tld = ""
    $contacts = @($Registrant, $AdministrativeContact, $TechnicalContact)

    if ($tldSplit.Length -gt 1)
    {

        $tld = $tldSplit[$tldSplit.Length - 1]
    }
    else
    {
        throw "Invalid domain name $DomainName"
    }

    $metdataCheck = @{
        tld = $tld
        contacts = $contacts
    }

  

    $Res = New-AnnexusWebRequest -Uri "$( $Annexus.Uri )/v2/drs/domain/tld-properties" -RequestMethod PUT -Body (ConvertTo-Json -Depth 10 @($metdataCheck))



    $Res

}

