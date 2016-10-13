sgesap_validation
=================

HP Serviceguard (SAP extensions) package validation script for Serviceguard A.11.20 and beyond. We can check a fresh package configuration file (use option `-f`) or use a configuration file (using `cmgetconf`) from the cluster itself. These two scripts should work on _HP-UX_ and _Linux_.

The purpose is to get an idea if the package is compliant with the specifications from the SAP customer.

    #-> /home/gdhaese1/bin/sgesap_validation.sh -h
    Usage: sgesap_validation.sh [-d] [-s] [-h] [-f] package_name

    -d:     Enable debug mode (by default off)
    -s:     Disable SGeSAP tetsing in package configuration file
    -f:     Force the read the local package_name.conf file instead of the one from cmgetconf
    -h:     Show usage [this page]

If we use the `-s` flag then we disable the SAP extentions tests.

    #-> /home/gdhaese1/bin/sgesap_validation.sh dbciOAC
    ###############################################################################################
                   Script: sgesap_validation.sh
                Arguments: dbciOAC
                  Purpose: Test the consistency of serviceguard (SGeSAP) configuration script
               OS Release: 11.31
                    Model: ia64
                     Host: sap01
                     User: root
                     Date: 2014-01-13 @ 14:55:25
                      Log: /var/adm/install-logs/sgesap_validation-20140113-1455.scriptlog
    ###############################################################################################
     ** Running on HP-UX 11.31                                                           [  OK  ]
     ** Serviceguard A.11.20.00 is valid                                                 [  OK  ]
     ** Serviceguard Extension for SAP B.05.10 is valid                                  [  OK  ]
     ** A valid cluster found, which is running                                          [  OK  ]
        HPXCL001       up
     ** Package directory (dbciOAC) found under /etc/cmcluster                           [  OK  ]
     ** Found configuration file /etc/cmcluster/dbciOAC/dbciOAC.conf                     [  OK  ]
     ** Found package_name (dbciOAC) in dbciOAC.conf                                     [  OK  ]
     ** Package dbciOAC is a configured package name (cluster HPXCL001)                  [  OK  ]
     ** Executing cmgetconf -p dbciOAC > /etc/cmcluster/dbciOAC/dbciOAC.conf.13Jan2014   [  OK  ]
     ** Found hostname (dbciOAC) in /etc/hosts on node sap01                             [  OK  ]
     ** Found hostname (dbciOAC) in /etc/hosts on node sap02                             [  OK  ]
     ** Found package_description (dbciOAC - Shaping The Future) in  dbciOAC.conf        [  OK  ]
     ** Found 2 node_name line(s) (sap01 sap02) in dbciOAC.conf                          [  OK  ]
     ** Found package_type (failover) in dbciOAC.conf                                    [  OK  ]
     ** Found auto_run (yes) in dbciOAC.conf                                             [  OK  ]
     ** Found node_fail_fast_enabled (no) in dbciOAC.conf                                [  OK  ]
     ** Found failover_policy (configured_node) in dbciOAC.conf                          [  OK  ]
     ** Found failback_policy (manual) in dbciOAC.conf                                   [  OK  ]
     ** Found run_script_timeout (no_timeout) in dbciOAC.conf                            [  OK  ]
     ** Found halt_script_timeout (no_timeout) in dbciOAC.conf                           [  OK  ]
     ** Found successor_halt_timeout (no_timeout) in dbciOAC.conf                        [  OK  ]
     ** Found priority (no_priority) in dbciOAC.conf                                     [  OK  ]
     ** Found ip_subnet (1 line(s)) in dbciOAC.conf                                      [  OK  ]
     ** Found ip_address (1 line(s)) in dbciOAC.conf                                     [  OK  ]
     ** Found local_lan_failover_allowed (yes) in dbciOAC.conf                           [  OK  ]
     ** Found script_log_file (/var/adm/cmcluster/log/dbciOAC.log) in dbciOAC.conf       [  OK  ]
     ** Found vgchange_cmd (vgchange -a e) in dbciOAC.conf                               [  OK  ]
     ** Found enable_threaded_vgchange (1) in dbciOAC.conf                               [  OK  ]
     ** Found concurrent_vgchange_operations (2) in dbciOAC.conf                         [  OK  ]
     ** Found fs_umount_retry_count (3) in dbciOAC.conf                                  [  OK  ]
     ** Found fs_mount_retry_count (3) in dbciOAC.conf                                   [  OK  ]
     ** Found concurrent_mount_and_umount_operations (3) in dbciOAC.conf                 [  OK  ]
     ** Found concurrent_fsck_operations (3) in dbciOAC.conf                             [  OK  ]
     ** user_name oacadm seems valid                                                     [  OK  ]
     ** user_host CLUSTER_MEMBER_NODE is valid                                           [  OK  ]
     ** user_role package_admin is valid                                                 [  OK  ]
     ** We found 1 vg (volume group) line(s) in dbciOAC.conf                             [  OK  ]
     ** Total amount of fs_ lines (86) in dbciOAC.conf must be even                      [  OK  ]
     ** VG /dev/vgdbOAC1 is not active on this node                                      [  OK  ]
     ** We will skip lvol and fs in-depth analysis; rerun when VG is active              [ SKIP ]
     ** module_name dbinstance present in dbciOAC.conf                                   [  OK  ]
     ** module_name db_global present in dbciOAC.conf                                    [  OK  ]
     ** module_name oracledb_spec present in dbciOAC.conf                                [  OK  ]
     ** module_name maxdb_spec present in dbciOAC.conf                                   [  OK  ]
     ** module_name sybasedb_spec present in dbciOAC.conf                                [  OK  ]
     ** module_name sapinstance present in dbciOAC.conf                                  [  OK  ]
     ** module_name sap_global present in dbciOAC.conf                                   [  OK  ]
     ** module_name stack present in dbciOAC.conf                                        [  OK  ]
     ** module_name sapinfra present in dbciOAC.conf                                     [  OK  ]
     ** module_name sapinfra_pre present in dbciOAC.conf                                 [  OK  ]
     ** module_name sapinfra_post present in dbciOAC.conf                                [  OK  ]
     ** sgesap/db_global/db_vendor set to oracle                                         [  OK  ]
     ** User oraoac home directory is /oracle/OAC                                        [  OK  ]
     ** User oacadm home directory is /home/oacadm                                       [  OK  ]
     ** Found entry 3619/tcp in /etc/services on node sap01                              [  OK  ]
     ** Found entry 3619/tcp in /etc/services on node sap02                              [  OK  ]
     ** sgesap/oracledb_spec/listener_name LISTENER_OAC                                  [  OK  ]
     ** sgesap/sap_global/sap_system OAC                                                 [  OK  ]
     ** sgesap/sap_global/rem_comm ssh                                                   [  OK  ]
     ** sgesap/sap_global/cleanup_policy normal                                          [  OK  ]
     ** sgesap/sap_global/retry_count 5                                                  [  OK  ]
     ** sgesap/stack/sap_instance ASCS19                                                 [  OK  ]
     ** sgesap/stack/sap_virtual_hostname dbciOAC                                        [  OK  ]
     ** sgesap/sapinfra/sap_infra_sw_type saposcol                                       [  OK  ]
     ** sgesap/sapinfra/sap_infra_sw_treat startonly                                     [  OK  ]
     ** Found module_names for nfs/hanfs                                                 [  OK  ]
     ** nfs/hanfs_export/SUPPORTED_NETIDS tcp                                            [  OK  ]
     ** nfs/hanfs_export/FILE_LOCK_MIGRATION 1                                           [  OK  ]
     ** nfs/hanfs_export/MONITOR_INTERVAL 10                                             [  OK  ]
     ** nfs/hanfs_export/MONITOR_LOCKD_RETRY 4                                           [  OK  ]
     ** nfs/hanfs_export/MONITOR_DAEMONS_RETRY 4                                         [  OK  ]
     ** nfs/hanfs_export/PORTMAP_RETRY 4                                                 [  OK  ]
     ** nfs/hanfs_flm/FLM_HOLDING_DIR /export/sapmnt/OAC/nfs_flm                         [  OK  ]
     ** nfs/hanfs_flm/NFSV4_FLM_HOLDING_DIR ""                                           [  OK  ]
     ** nfs/hanfs_flm/PROPAGATE_INTERVAL 5                                               [  OK  ]
     ** nfs/hanfs_flm/STATMON_WAITTIME 90                                                [  OK  ]
     ** nfs/hanfs_export/XFS /export/sapmnt/OAC (directory exists)                       [  OK  ]
     ** The XFS access list "root=" matches the "rw=" for /export/sapmnt/OAC             [  OK  ]
     ** The XFS access list "ro=dbciOAC" is correct                                      [  OK  ]
     ** /sapmnt/OAC in /etc/auto.direct (on node sap01) uses "tcp" to mount              [  OK  ]
     ** /sapmnt/OAC in /etc/auto.direct (on node sap02) uses "tcp" to mount              [  OK  ]
     ** $SGCONF/scripts/ext/tidal_ext_script.sh defined in dbciOAC.conf                  [  OK  ]
     ** DEBUG file /var/adm/cmcluster/debug_dbciOAC NOT found                            [  OK  ]
    
            *************************************************************************
              No errors were found in /etc/cmcluster/dbciOAC/dbciOAC.conf
              Run "cmcheckconf -v -P /etc/cmcluster/dbciOAC/dbciOAC.conf"
              followed by "cmapplyconf -v -P /etc/cmcluster/dbciOAC/dbciOAC.conf"
            *************************************************************************
            Log file is saved as /var/adm/install-logs/sgesap_validation-20140113-1455.scriptlog
    

