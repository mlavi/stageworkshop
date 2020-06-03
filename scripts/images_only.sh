#!/usr/bin/env bash
#####################################################
# Images Inly distribution script                   #
# ------------------------------------------------- #
# Willem Essenstam -  0.1 - 15 March 2020           #
#                     Initial version               #
#####################################################

#__main()__________
# Source Nutanix environment (PATH + aliases), then common routines + global variables
. /etc/profile.d/nutanix_env.sh
. we-lib.common.sh
. global.vars.sh

# Try to figure out what workshop we have run
# Which log files do we have?
log_files=$(ls *.log)

images_arr=("CentOS7.qcow2" "Windows2012R2.qcow2" "Windows10-1709.qcow2" "WinToolsVM.qcow2" "Linux_ToolsVM.qcow2" \
        "ERA-Server-build-1.2.1.qcow2" "MSSQL-2016-VM.qcow2" "hycu-3.5.0-6253.qcow2" "VeeamAvailability_1.0.457.vmdk" "move3.2.0.qcow2" \
        "AutoXD.qcow2" "CentOS7.iso" "Windows2016.iso" "Windows2012R2.iso" "Windows10.iso" "Nutanix-VirtIO-1.1.5.iso" "SQLServer2014SP3.iso" \
        "XenApp_and_XenDesktop_7_18.iso" "VeeamBR_9.5.4.2615.Update4.iso" "Windows2016.qcow2" "ERA-Server-build-1.2.1.qcow2" "Win10v1903.qcow2"  \
        "Linux_ToolsVM.qcow2" "move-3.4.1.qcow2" "GTSOracle/19c-april/19c-bootdisk.qcow2" "GTSOracle/19c-april/19c-disk1.qcow2" "GTSOracle/19c-april/19c-disk2.qcow2" \
        "GTSOracle/19c-april/19c-disk3.qcow2" "GTSOracle/19c-april/19c-disk4.qcow2" "GTSOracle/19c-april/19c-disk5.qcow2" "GTSOracle/19c-april/19c-disk6.qcow2" \
        "GTSOracle/19c-april/19c-disk7.qcow2" "GTSOracle/19c-april/19c-disk8.qcow2" "GTSOracle/19c-april/19c-disk9.qcow2" "HYCU/Mine/HYCU-4.0.3-Demo.qcow2" \
        "veeam/VeeamAHVProxy2.0.404.qcow2" "Citrix_Virtual_Apps_and_Desktops_7_1912.iso" "FrameCCA-2.1.6.iso" "FrameCCA-2.1.0.iso" "FrameGuestAgentInstaller_1.0.2.2_7930.iso" \
        "veeam/VBR_10.0.0.4442.iso")

if [[ $log_files == *"snc_bootcamp"* ]]; then
  # We have found snc_bootcamp has been run
  workshop="snc_bootcamp"
  send_img_array=(${images_arr[@]:0:20})
elif [[ $log_files == *"basic_bootcamp"* ]]; then
  # We have found basic_bootcamp has been run
  workshop="basic_bootcamp"
  send_img_array=(${images_arr[13]} ${images_arr[0]} ${images_arr[15]} ${images_arr[14]})
elif [[ $log_files == *"privatecloud_bootcamp"* ]]; then
  # We have found privatecloud_bootcamp has been run
  workshop="privatecloud_bootcamp"
elif [[ $log_files == *"era_bootcamp"* ]]; then
  # We have found era_bootcamp has been run
  workshop="era_bootcamp"
elif [[ $log_files == *"files_bootcamp"* ]]; then
  # We have found files_bootcamp has been run
  workshop="files_bootcamp"
elif [[ $log_files == *"calm_bootcamp"* ]]; then
  # We have found calm_bootcamp has been run
  workshop="calm_bootcamp"
elif [[ $log_files == *"citrix_bootcam"* ]]; then
  # We have found citrix_bootcamp has been run
  workshop="citrix_bootcamp"
elif [[ $log_files == *"frame_bootcamp"* ]]; then
  # We have found frame_bootcamp has been run
  workshop="frame_bootcamp"
elif [[ $log_files == *"bootcamp"* ]]; then
  # We have fond that the bootcamp has been run
  workshop="bootcamp"
  send_img_array=(${images_arr[@]:0:20})
elif [[ $log_files == *"ts2020"* ]]; then
  # We have fond that the ts2020 has been run
  workshop="ts2020"
  send_img_array=(${images_arr[0]} ${images_arr[@]:20:41})
fi

# Make the right images avail for the different workshops based on the one we found from the log file
case $workshop in
    "snc_bootcamp")
        echo "Found the SNC_Bootcamp has run."
        ;;
    "basic_bootcamp")
        echo "basic_bootcamp found"
        ;;
    "privatecloud_bootcamp")
        echo "privatecloud_bootcamp found"
        ;;
    "era_bootcamp")
        echo "Era_bootcamp found"
        ;;
    "files_bootcamp")
        echo "files_bootcamp found"
        ;;
    "calm_bootcamp")
        echo "calm_bootcamp found"
        ;;
    "citrix_bootcamp")
        echo "citrix_bootcamp found"
        ;;
    "frame_bootcamp")
        echo "frame_bootcamp found"
        ;;
    "bootcamp")
        echo "bootcamp found"
        ;;
 esac








