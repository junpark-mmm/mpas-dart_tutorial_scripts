#!/bin/tcsh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
#set echo
########################################################################################
# you can also download data from NCAR RDA (https://rda.ucar.edu/datasets/d084001/)
# wget https://data.rda.ucar.edu/d084001/2019/20190417/gfs.0p25.2019041700.f000.grib2
#
# Download GFS or GEFS ensemble grib2 data from AWS S3 (data available after Oct 2021)
#
# This script is designed to download GFS or GEFS grib2 from AWS to construct 
# initial BKG ensemble for MPAS-DART tutorial
# It will download GFS/GEFS grib2 at analysis time (not forecast hours) 
# This will parse some information from param.tcsh but you also need to input the below argument
# $1: Initial date for Data download   (Format: YYYYMMDDHH; 2019041700)
# $2: Final date for Data download     (Format: YYYYMMDDHH; 2019041700)
# $3: Location of your params.tcsh
# 
# Required: wget
# ./download.tcsh 2019041700 2019041700 params.tcsh
#########################################################################################!/bin/sh


if ( $#argv >= 3 ) then
   set IDATE      = ${1} 
   set EDATE      = ${2} 
   set fn_param   = ${3}
else
   echo three arguments are required Cannot proceed.
   echo \$\1: IDATE \$\2: EDATE \$\3: params.tcsh
   echo date format is YYYYMMDDHH \(e\.g\.\, 2019041700\)
   exit
endif

if(! -e $fn_param ) then
   echo $fn_param does not exist. Cannot proceed.
   exit
endif

source ${fn_param}

set INT_HR     = 6              # Interval of GFS/EFS Data (every 6 hour)
set FCST_HR    = 000      # if you are going to use forecast grib2, add loop for $FCST_HR

if ( $IDATE >= 2021100100 ) then # use AWS S3
   echo "use AWS S3"
#
   if ( ${EXT_DATA_TYPE} == "GFS" ) then # GFS data and then use DART to add perturbations
      set DATA_URL         = "https://noaa-gfs-bdp-pds.s3.amazonaws.com"
      set N_ENS_MEMBER    = 1
      set PREFIX_DATA     = "gfs"
      set RESOLUTION_DATA = "0p25"
   else if ( ${EXT_DATA_TYPE} == "GFSENS" ) then # GEFS data to create ensemble
      set DATA_URL         = "https://noaa-gefs-pds.s3.amazonaws.com"
      set N_ENS_MEMBER    = ${ENS_SIZE} # # of ensemble member to download (for GEFS)
      set PREFIX_DATA     = "gep"
      set RESOLUTION_DATA = "0p50"
   else
      echo "please use GFS or GFSENS when using download.csh with AWS S3"
      exit
   endif

   set CDATE      = $IDATE
   while ( $CDATE <= $EDATE ) # Main loop for time
      # Current Time
      set CYYYY = `echo $CDATE |  cut -c1-4`
      set   CMM = `echo $CDATE |  cut -c5-6`
      set   CDD = `echo $CDATE |  cut -c7-8`
      set   CHH = `echo $CDATE | cut -c9-10`
      foreach MEM (`seq -w 01 1 ${N_ENS_MEMBER}`) # Loop for member
         # set directory for GFS or GEFS
         if ( ${EXT_DATA_TYPE} == "GFS" ) then 
             set TEMP_DIR = ${EXTM_DIR}/${CDATE} # no need for members
         else if ( ${EXT_DATA_TYPE} == "GFSENS" ) then 
             set TEMP_DIR = ${EXTM_DIR}/${MEM}/${CDATE}
         endif

         mkdir -p ${TEMP_DIR}
         cd ${TEMP_DIR}

         # if you are going to use GEFS forecast grib2, add loop for $FCST_HR
         if ( ${EXT_DATA_TYPE} == "GFS" ) then 
            wget ${DATA_URL}/${PREFIX_DATA}.${CYYYY}${CMM}${CDD}/${CHH}/atmos/${PREFIX_DATA}.t${CHH}z.pgrb2.${RESOLUTION_DATA}.f${FCST_HR}
         else if ( ${EXT_DATA_TYPE} == "GFSENS" ) then 
            foreach INFIX ( a b ) # Loop for pgrb2a and pgrb2b for GEFS
               wget ${DATA_URL}/gefs.${CYYYY}${CMM}${CDD}/${CHH}/atmos/pgrb2${INFIX}p5/${PREFIX_DATA}${MEM}.t${CHH}z.pgrb2${INFIX}.${RESOLUTION_DATA}.f${FCST_HR}
               # merge into a single file
               cat ${PREFIX_DATA}${MEM}.t${CHH}z.pgrb2${INFIX}.${RESOLUTION_DATA}.f${FCST_HR} >> ${PREFIX_DATA}${MEM}.t${CHH}z.pgrb2.${RESOLUTION_DATA}.f${FCST_HR}
               ${REMOVE} -rf ${PREFIX_DATA}${MEM}.t${CHH}z.pgrb2${INFIX}.${RESOLUTION_DATA}.f${FCST_HR}
            end
         endif
         touch ready.txt # can be used to check external data is ready in workflow
         sleep 5
      end
      # Update CDATE with INT_HR
      set CDATE = `date -d"${CHH}:00:00 ${CYYYY}-${CMM}-${CDD} +${INT_HR} hours" +"%Y%m%d%H"` # forward by $INT_HR
   end

else  # use NCAR RDA
   echo "use NCAR RDA DS084001"
   echo $EXT_DATA_TYPE
   if ( ${EXT_DATA_TYPE} == "GFSENS" ) then 
      echo "GFSENS is not available at NCAR RDA"
      exit
   else
      echo "Use GFS"
   endif

   set CDATE      = $IDATE
   while ( $CDATE <= $EDATE ) # Main loop for time

      # Current Time
      set CYYYY = `echo $CDATE |  cut -c1-4`
      set   CMM = `echo $CDATE |  cut -c5-6`
      set   CDD = `echo $CDATE |  cut -c7-8`
      set   CHH = `echo $CDATE | cut -c9-10`
      set TEMP_DIR = ${EXTM_DIR}/${CDATE} # no need for members

      mkdir -p ${TEMP_DIR}
      cd ${TEMP_DIR}

      set DATA_URL = "https://data.rda.ucar.edu/d084001"
      set PREFIX_DATA     = "gfs"
      set RESOLUTION_DATA = "0p25"

      wget ${DATA_URL}/${CYYYY}/${CYYYY}${CMM}${CDD}/${PREFIX_DATA}.${RESOLUTION_DATA}.${CDATE}.f${FCST_HR}.grib2
      touch ready.txt # can be used to check external data is ready in workflow
      sleep 5

      # Update CDATE with INT_HR
      set CDATE = `date -d"${CHH}:00:00 ${CYYYY}-${CMM}-${CDD} +${INT_HR} hours" +"%Y%m%d%H"` # forward by $INT_HR
   end

endif
