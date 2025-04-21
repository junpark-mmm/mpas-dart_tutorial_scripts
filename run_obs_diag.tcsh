#!/bin/tcsh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
##############################################################################################
#  run_obs_diag.tcsh
#  This will run ob_diag to compute obs diagnostics from obs_sequence file
#
# INPUT: obs_seq.final
# OUTPUT: obs_diag_${DATE}.nc
#
# this is not using PBS
##############################################################################################

#set echo
set SEPARATE_DOMAIN = false # extend verification domains (5 in default; see line #197)
                           # global,   NH,    SH,   Tropic, and CONUS
	                   # -80~80, 20~80, -80~-20, -20~20,     20~55   ; lat
	                   #  0~360, 0~360,   0~360,  0~360     230~310  ; lon

if ( $#argv >= 4 ) then
   set sdate = ${1}
   set edate = ${2}
   set interval_hour = ${3}
   set fn_param = `readlink -f ${4}`
else
   echo four arguments are required. Cannot proceed.
   echo \$\1: SDATE \$\2: EDATE \$\3: INTERVAL_HOUR \$\4: params.tcsh
   echo date format is YYYYMMDDHH (e.g., 2024050600)
   exit
endif

if (! -e $fn_param ) then
   echo $fn_param does not exist. Cannot proceed.
   exit
endif

module list
source $fn_param

#--------------------------------------------------------------------------
# Experiment name and the cycle period
#--------------------------------------------------------------------------
echo Experiment name: $EXPERIMENT_NAME

####################################################################################
# END OF USER SPECIFIED PARAMETERS
####################################################################################

if( ! -e $RUN_DIR ) mkdir -p $RUN_DIR

#fn_param will have absolute path; no need to copy

cd $RUN_DIR
echo Running $0 in $RUN_DIR
echo

echo "This script is not utilizing PBS" 

#------------------------------------------
# Check if we have all the necessary files.
#------------------------------------------

# FILELIST
set  FILELIST = ( obs_diag advance_time )
foreach fn ( $FILELIST )
   if ( ! -x $fn ) then
      echo ${LINK} ${EXE_DIR}/${fn} .
           ${LINK} ${EXE_DIR}/${fn} .
      if ( ! $status == 0 ) then
         echo ABORT\: We cannot find required executable dependency $fn.
         exit
      endif
   endif
end 

#  Check to see if MPAS and DART namelists exist. If not, copy them from template
   foreach fn ( ${NML_DART} )
      if ( ! -r ${fn} ) then
         ${COPY} ${TEMPLATE_DIR}/${fn} .
      endif
      if ( ! $status == 0 ) then
         echo ABORT\: We cannot find required script $fn.
         exit
      endif
   end

#------------------------------------------
# Time info
#------------------------------------------
# sdate - greg_beg
# edate - greg_end
# intv_second -> intv_hr
echo $sdate $edate
set DATE_BEG = `echo "${sdate} 0 -w"| ./advance_time` #"${syyyy}-${smm}-${sdd}_${shh}:00:00"
set DATE_END = `echo "${edate} 0 -w"| ./advance_time` #"${eyyyy}-${emm}-${edd}_${ehh}:00:00"
echo $DATE_BEG $DATE_END
set intv_second = `expr ${interval_hour} \* 3600`
set greg_beg = `echo $DATE_BEG 0 -g | ./advance_time`
set greg_end = `echo $DATE_END 0 -g | ./advance_time`
echo $intv_second $greg_beg $greg_end
set  intv_hr = `expr $intv_second \/ 3600`
set diff_day = `expr $greg_end[1] \- $greg_beg[1]`
set diff_sec = `expr $greg_end[2] \- $greg_beg[2]`
set diff_tot = `expr $diff_day \* 86400 \+ $diff_sec`
set n_cycles = `expr $diff_tot \/ $intv_second \+ 1`

echo "Total of ${n_cycles} cycles from $DATE_BEG to $DATE_END will be run every $intv_hr hr."

if($n_cycles < 0) then
   echo Cannot figure out how many cycles to run. Check the time setup.
   exit
endif

echo " "

#------------------------------------------
# Initial ensemble for $DATE_INI
#------------------------------------------
# check if data are available from driver_initial_ens.csh

#--------------------------------------------------------
# Cycling gets started
#--------------------------------------------------------

# update logic - time_anl will be updated ${intv_hr}
set time_anl = ${sdate}
set time_end = ${edate}
# make temoporary directory
  set temp_work_dir = ${RUN_DIR}/obs_diag_netcdf
  if ( -d ${temp_work_dir} )  ${REMOVE} ${temp_work_dir}
  mkdir -p ${temp_work_dir}
  cd ${temp_work_dir}

  ${LINK} ${RUN_DIR}/advance_time                      .   || exit 1
  ${LINK} ${RUN_DIR}/obs_diag                          .   || exit 1
  ${COPY} ${RUN_DIR}/input.nml                         .   || exit 1

  set sav_dir = ${OBS_DIR}
  mkdir -p ${sav_dir}

while ( $time_anl <= $time_end )
#
  set time_nxt = `echo $time_anl +$intv_hr | ./advance_time`	#YYYYMMDDHH
  set anal_utc = `echo $time_anl 0 -w | ./advance_time`
  set greg_obs = `echo $time_anl 0 -g | ./advance_time`
  set greg_obs_days = $greg_obs[1]
  set greg_obs_secs = $greg_obs[2]

  echo Processing at ${time_anl}\: ${greg_obs_days}_${greg_obs_secs}
#
#------------------------------------------------------
# This part can be separated in a different shell script if several model needs to be supported
#------------------------------------------------------
#
# Namelist update
# variables to be updated at input.nml
#
# if OBS seq file is not exist stop
# if hour format is 24; create simlink for that
#
set obs_file  = obs_seq.final

   foreach fn ( ${obs_file} )
      if ( ! -e ${fn} ) then
         ${COPY} ${OUTPUT_DIR}/${time_anl}/${fn} .
         if ( ! $status == 0 ) then
            echo ABORT\: We cannot find required obs $fn at ${OBS_DIR}.
            exit
         endif
      endif
   end

#------------------------------------------
# Time info

set time_anl_yyyy = `echo $time_anl | cut -c1-4`
set time_anl_mm   = `echo $time_anl | cut -c5-6`
set time_anl_dd   = `echo $time_anl | cut -c7-8`
set time_anl_hh   = `echo $time_anl | cut -c9-10`

cat >! dart.sed << EOF
  /obs_sequence_name/c\
   obs_sequence_name = '${obs_file}'
  /first_bin_center /c\
   first_bin_center = ${time_anl_yyyy},${time_anl_mm},${time_anl_dd},${time_anl_hh},00,00
  /last_bin_center /c\
   last_bin_center = ${time_anl_yyyy},${time_anl_mm},${time_anl_dd},${time_anl_hh},00,00
EOF

   if ( ${SEPARATE_DOMAIN} == "true" ) then

cat >> dart.sed << EOF
  /nregions/c\
   nregions  = 5
  /lonlim1/c\
   lonlim1   =   0.0,   0.0,   0.0,   0.0, 230.0
  /lonlim2/c\
   lonlim2   = 360.0, 360.0, 360.0, 360.0, 310.0
  /latlim1/c\
   latlim1   = -80.0,  20.0, -80.0, -20.0,  20.0
  /latlim2/c\
   latlim2   =  80.0,  80.0, -20.0,  20.0,  55.0
  /reg_name/c\
   reg_names = 'GLOBAL', 'NH', 'SH', 'TR', 'CONUS'
EOF
   endif

sed -f dart.sed ${RUN_DIR}/${NML_DART} >! input.nml

if ( ${NML_DART} != input.nml ) then
     set NML_DART = input.nml
endif

set fn_grid_def = `grep init_template_filename ${NML_DART} | awk '{print $3}' | cut -d ',' -f1 | sed -e "s/'//g" | sed -e 's/"//g'`
set F_TEMPLATE = `ls -1 ${INIT_DIR}/*/*/${MPAS_GRID}.init.nc | head -1`
echo $fn_grid_def

if ( ! -r $fn_grid_def ) then
  ${LINK} ${F_TEMPLATE} $fn_grid_def    || exit
endif

#
# run mpas_dart_obs_preprocess
./obs_diag > log_${time_anl}

# copy and clean-up
${COPY} obs_diag_output.nc ${OUTPUT_DIR}/${time_anl}/obs_diag_${time_anl}.nc
${REMOVE} obs_diag_output.nc ${obs_file}

  set time_anl = ${time_nxt}
end
#
echo Script exiting normally.

exit 0
