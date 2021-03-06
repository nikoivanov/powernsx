#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "LogicalSwitching" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        # Prefix to use for different variables.
        $script:tzPrefix = "pester_tz"
        $script:lsPrefix = "pester_ls"
        $script:ls1_name = "$lsPrefix-ls1"
        $script:ls2_name = "$lsPrefix-ls2"
        $script:tzLocal2_name = "$tzPrefix-tzlocal2"
        $script:tzLocal = Get-NsxTransportZone -LocalOnly | select -first 1
        $script:tzLocal2 = New-NsxTransportZone -Name $tzLocal2_name -cluster (get-cluster | select -first 1) -ControlPlaneMode UNICAST_MODE

    }

    AfterAll {

        Get-NsxTransportZone | ? {$_.name -match $tzPrefix } | remove-NsxTransportZone -confirm:$false

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        disconnect-nsxserver
    }

    AfterEach {
        # Cleanup Testing Logical Switches
        Get-NsxTransportZone | Get-NsxLogicalSwitch | ? {$_.name -match $lsPrefix} | Remove-NsxLogicalSwitch -confirm:$false

    }

    Context "Logical Switches" {
        it "Can create a logical switch" {
            Get-NsxTransportZone -LocalOnly | select -first 1 | new-nsxlogicalswitch $ls1_name
            get-nsxlogicalswitch $ls1_name | should not be $null
        }

        it "Can remove a logical switch"{
            Get-NsxTransportZone -LocalOnly | select -first 1 | new-nsxlogicalswitch $ls1_name
            get-nsxlogicalswitch $ls1_name | Remove-NsxLogicalSwitch -Confirm:$false
            get-nsxlogicalswitch $ls1_name | should be $null
        }

        it "Can retrive logical switches from a specific transport zone via pipeline" {
            $ls1 = $tzlocal | new-nsxlogicalswitch $ls1_name
            $ls2 = $tzlocal2 | New-NsxLogicalSwitch $ls2_name
            $ls = $tzlocal2 | Get-NsxLogicalSwitch
            $ls | should not be $null
            @($ls).count | should be 1
            $ls.name | should be $ls2_name
        }

        it "Can retrive logical switches from a specific transport zone via vdnscope parameter" {
            $ls1 = $tzlocal | new-nsxlogicalswitch $ls1_name
            $ls2 = $tzlocal2 | New-NsxLogicalSwitch $ls2_name
            $ls = Get-NsxLogicalSwitch -vdnscope $tzlocal2
            $ls | should not be $null
            @($ls).count | should be 1
            $ls.name | should be $ls2_name
        }
    }

    Context "Transport Zones" {

        BeforeAll {

            $script:tzPrefix = "pester_tz"
            $script:tzMember_name = "$tzPrefix-tzmember"
            $script:tzUniversal = Get-NsxTransportZone -UniversalOnly
            #Create the TZ we will modify.
            $emptycl = ($tzLocal).clusters.cluster.cluster.name | % {get-cluster $_ } | ? { ($_ | get-vm | measure).count -eq 0 }
            if ( -not $emptycl ) {
                write-warning "No cluster that is a member of an NSX TransportZone but not hosting any VMs could be found for Transport Zone membership addition/removal tests."
                $script:SkipTzMember = $True
            }
            else {
                $script:cl = $emptycl | select -First 1
                $script:SkipTzMember = $False
                $script:tzmember = New-NsxTransportZone -Name $tzmember_name -cluster $cl -ControlPlaneMode UNICAST_MODE
                write-warning "Using $($tzmember.Name) and cluster $cl for transportzone membership test"
            }

        }

        AfterAll {
            $Tzmember | Remove-NsxTransportZone -confirm:$false
        }

        it "Can retrieve a transport zone by id" -skip:$SkipTzMember {
            $temptz = Get-NsxTransportZone -objectId $Tzmember.objectId
            $temptz | should not be $null
            @($temptz).count | should be 1
            $temptz.objectId | should be $Tzmember.objectId
        }

        it "Can retrieve a transport zone by name" -skip:$SkipTzMember {
            $temptz = Get-NsxTransportZone -Name $tzmember.name
            $temptz | should not be $null
            @($temptz).count | should be 1
            $temptz.Name | should be $Tzmember.Name
        }

        it "Can retrieve local and universal transport zones" -skip:$SkipTzMember {
            $temptz = Get-NsxTransportZone
            $temptz | should not be $null
            @($temptz).count | should begreaterthan 1
            $temptz | where-object { $_.IsUniversal -eq "false"}  | should not be $null
            $temptz | where-object { $_.IsUniversal -eq "true"}  | should not be $null
        }

        it "Can retrieve localonly tz by name" -skip:$SkipTzMember {
            $temptz = Get-NsxTransportZone -LocalOnly -Name $tzmember_name
            $temptz | should not be $null
            @($temptz).count | should be 1
            $temptz.Name | should be $tzmember_name
            $temptz.IsUniversal | should be "false"
        }

        it "Can retrieve universalonly tz by name" -skip:$SkipTzMember {
            $temptz = Get-NsxTransportZone -UniversalOnly -Name $tzuniversal.name
            $temptz | should not be $null
            @($temptz).count | should be 1
            $temptz.Name | should be $tzuniversal.name
            $temptz.IsUniversal | should be "true"
        }

        it "Can remove a transportzone cluster" -skip:$SkipTzMember {
            $Tzmember | Remove-NsxTransportZoneMember -Cluster $cl
            $updatedtz = Get-NsxTransportZone -objectId $Tzmember.objectId
            $updatedtz.clusters.cluster.cluster.name -contains $cl.name | should be $false
        }

        it "Can add a transportzone cluster" -skip:$SkipTzMember {
            $Tzmember | Add-NsxTransportZoneMember -Cluster $cl
            $updatedtz = Get-NsxTransportZone -objectId $Tzmember.objectId
            $updatedtz.clusters.cluster.cluster.name -contains $cl.name | should be $true
        }
    }
}

