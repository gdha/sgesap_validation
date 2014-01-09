sgesap_validation
=================

HP Serviceguard (SAP extensions) package validation script for Serviceguard A.11.20 and beyond. We can check a fresh package configuration file (use option `-f`) or use a configuration file (using `cmgetconf`) from the cluster itself.

The purpose is to get an idea if the package is compliant with the specifications from the SAP customer.

    #-> /home/gdhaese1/bin/sgesap_validation.sh -h
    Usage: sgesap_validation.sh [-d] [-s] [-h] [-f] package_name

    -d:     Enable debug mode (by default off)
    -s:     Disable SGeSAP tetsing in package configuration file
    -f:     Force the read the local package_name.conf file instead of the one from cmgetconf
    -h:     Show usage [this page]

If we use the `-s` flag then we disable the SAP extentions tests.
