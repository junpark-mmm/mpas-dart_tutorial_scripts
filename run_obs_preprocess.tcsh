#!/bin/tcsh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
##############################################################################################
#  run_obs_diag.csh
#  This will run ob_diag to process OBS diagnostics from obs_seq.final after filter
# e.g., SuperOB, elevation check, QC update, ....
#
# INPUT: ${OUTPUT_DIR}/${DATE}/obs_seq.final
# OUTPUT: ${OUTPUT_DIR}/${DATE}/obs_diag_${DATE}.nc
#
# this script does not utilize PBS
#
##############################################################################################

#set echo

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
set  FILELIST = ( mpas_dart_obs_preprocess advance_time )
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
  set temp_work_dir = ${RUN_DIR}/obs_preprocess
  if ( -d ${temp_work_dir} )  ${REMOVE} ${temp_work_dir}
  mkdir -p ${temp_work_dir}
  cd ${temp_work_dir}

  ${LINK} ${RUN_DIR}/advance_time                      .   || exit 1
  ${LINK} ${RUN_DIR}/mpas_dart_obs_preprocess          .   || exit 1
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
set obs_file  = obs_seq${time_anl}

   foreach fn ( ${obs_file} )
      if ( ! -e ${fn} ) then
         ${COPY} ${OBS_DIR}/${fn} .
         if ( ! $status == 0 ) then
             # change time for 00h -> D-1 24h
             echo "$fn is not available; let's have another search in case of 00hr"
             set fn_chk = obs_seq`echo $time_anl -24 | ./advance_time | cut -c1-8`24
             if ( -e ${OBS_DIR}/${fn_chk} ) then
                 echo "$fn_chk is found; use this file"
                 ${LINK} ${OBS_DIR}/${fn_chk} ${fn}
             else
                 echo ABORT\: We cannot find required obs $fn at ${OBS_DIR}.
                 exit
             endif
         endif
      endif
   end

#------------------------------------------
# Time info

set file_name_input  = ${obs_file}
set file_name_output = ${obs_file}_after

# may need changes depending on your  configuration.
set superob_aircraft         = .true.
set superob_sat_winds        = .true.
set sfc_elevation_check      = .true.
set sfc_elevation_tol        = 100.0
set overwrite_ncep_sfc_qc    = .true.
set overwrite_ncep_satwnd_qc = .true.
set windowing_int_hour       = 1.
set increase_bdy_error       = .false.
set obsdistbdy               = 90000.0

  cat >! dart.sed << EOF
  /file_name_input /c\
   file_name_input = '${file_name_input}'
  /file_name_output /c\
   file_name_output = '${file_name_output}'
  /superob_aircraft /c\
   superob_aircraft = ${superob_aircraft}
  /superob_sat_winds /c\
   superob_sat_winds = ${superob_sat_winds}
  /sfc_elevation_check /c\
   sfc_elevation_check = ${sfc_elevation_check}
  /sfc_elevation_tol /c\
   sfc_elevation_tol = ${sfc_elevation_tol}
  /overwrite_ncep_sfc_qc /c\
   overwrite_ncep_sfc_qc = ${overwrite_ncep_sfc_qc}
  /overwrite_ncep_satwnd_qc /c\
   overwrite_ncep_satwnd_qc = ${overwrite_ncep_satwnd_qc}
  /windowing_int_hour /c\
   windowing_int_hour = ${windowing_int_hour}
  /increase_bdy_error /c\
   increase_bdy_error = ${increase_bdy_error}
  /obsdistbdy /c\
   obsdistbdy = ${obsdistbdy}
EOF
sed -f dart.sed ${RUN_DIR}/${NML_DART} >! input.nml

if ( ${NML_DART} != input.nml ) then
     set NML_DART = input.nml
endif

set fn_grid_def = `grep init_template_filename ${NML_DART} | awk '{print $3}' | cut -d ',' -f1 | sed -e "s/'//g" | sed -e 's/"//g'`
set F_TEMPLATE = `ls -1 ${INIT_DIR}/*/*/${MPAS_GRID}.init.nc | head -1`

if ( ! -r $fn_grid_def ) then
  ${LINK} ${F_TEMPLATE} $fn_grid_def    || exit
endif

#
# run mpas_dart_obs_preprocess
echo "${greg_obs_days}, ${greg_obs_secs}" | ./mpas_dart_obs_preprocess > log_${time_anl}

# copy and clean-up
${COPY} ${file_name_output} ${OBS_DIR}
#${REMOVE} ${file_name_input} ${file_name_output}

  set time_anl = ${time_nxt}
end
#
echo Script exiting normally.

exit 0
