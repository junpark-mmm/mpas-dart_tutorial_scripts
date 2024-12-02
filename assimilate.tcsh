#!/bin/tcsh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
# DART $Id$
#
##==================================================================
# assimilate.tcsh - copy and update files for filter job
#                  then run filter; and store files
# 
##==================================================================
set time_anl     =  ${1}
set intv_second  =  ${2}
set paramfile    =  ${3}

source ${paramfile}

set start_time = `date +%s`

cd ${RUN_DIR}

echo $start_time >&! filter_started

set job_dir = ${RUN_DIR}/filter.${time_anl}
if ( -d ${job_dir} )  ${REMOVE} ${job_dir}
mkdir -p ${job_dir}
cd ${job_dir}

#  Get the program and necessary files for the model
  ${LINK} ${RUN_DIR}/filter                            .   || exit 1
  ${LINK} ${RUN_DIR}/advance_time                      .   || exit 1

# time
set  INTV_DAY  = 0
set  INTV_SEC  = `echo $intv_second`
set  intv_hr   = `expr $intv_second \/ 3600`

while ( $INTV_SEC >= 86400 )
     @ INTV_DAY++
     @ INTV_SEC = $INTV_SEC - 86400
end
# dart
# maybe used for LBC treatment

#--------------------------------------------------------------------------
# Edit input.nml
#--------------------------------------------------------------------------
  cat >! dart.sed << EOF
  /ens_size /c\
   ens_size                 = ${ENS_SIZE}
  /num_output_obs_members /c\
   num_output_obs_members   = ${num_output_obs_members}
  /num_output_state_members/c\
   num_output_state_members = ${num_output_state_members}
  /assimilation_period_days /c\
   assimilation_period_days     = ${INTV_DAY}
  /assimilation_period_seconds /c\
   assimilation_period_seconds  = ${INTV_SEC}
  /cutoff /c\
   cutoff                       = ${CUTOFF}
  /vert_normalization_height /c\
   vert_normalization_height   = ${VLOC}
  /distribute_mean /c\
   distribute_mean              = .${DISTRIB_MEAN}.
  /convert_all_obs_verticals_first /c\
   convert_all_obs_verticals_first   = .${CONVERT_OBS}.
  /convert_all_state_verticals_first /c\
   convert_all_state_verticals_first = .${CONVERT_STAT}.
  /write_binary_obs_sequence /c\
   write_binary_obs_sequence = .${binary_obs_seq}.
  /tasks_per_node /c\
   tasks_per_node = ${N_PROCS_ANAL}
EOF
sed -f dart.sed ${RUN_DIR}/${NML_DART} >! input.nml

if ( ${NML_DART} != input.nml ) then
     set NML_DART = input.nml
endif

##--------------------------------------------------------------------------
##  Take file names from input.nml, check to make sure there is consistency in variables.
##--------------------------------------------------------------------------
set  input_list = `grep input_state_file_list  ${NML_DART} | awk '{print $3}' | cut -d ',' -f1 | sed -e "s/'//g" | sed -e 's/"//g'`
set output_list = `grep output_state_file_list ${NML_DART} | awk '{print $3}' | cut -d ',' -f1 | sed -e "s/'//g" | sed -e 's/"//g'`
set  obs_seq_in = `grep obs_sequence_in_name   ${NML_DART} | awk '{print $3}' | cut -d ',' -f1 | sed -e "s/'//g" | sed -e 's/"//g'`
set obs_seq_out = `grep obs_sequence_out_name  ${NML_DART} | awk '{print $3}' | cut -d ',' -f1 | sed -e "s/'//g" | sed -e 's/"//g'`
#
set fn_grid_def = `grep init_template_filename ${NML_DART} | awk '{print $3}' | cut -d ',' -f1 | sed -e "s/'//g" | sed -e 's/"//g'`

set F_TEMPLATE = `ls -1 ${INIT_DIR}/*/*/${MPAS_GRID}.init.nc | head -1`

if ( ! -r $fn_grid_def ) then
  ${LINK} ${F_TEMPLATE} $fn_grid_def    || exit
endif

# check time
  set time_pre = `echo $time_anl -$intv_hr | ./advance_time`    #YYYYMMDDHH
  set anal_utc = `echo $time_anl 0 -w | ./advance_time`


# check inflation files at time previous hour interval
  if ( $ADAPTIVE_INF == true ) then
    if ( ! -e ${OUTPUT_DIR}/${time_pre}/${INFL_OUT}_mean.nc ) then
      echo ${OUTPUT_DIR}/${time_pre}/${INFL_OUT}_mean.nc does not exist.
      set exist_infl_out_file = `find ${OUTPUT_DIR}/*/ -name "${INFL_OUT}_mean.nc" -print -quit | wc -l || echo 0`
      if ( ${exist_infl_out_file} > 0 ) then
         echo however, ${OUTPUT_DIR} has some inf files on other dates
         echo please check your directories
         exit
      else
         echo "however, there is no inflation file at ${OUTPUT_DIR}"
         echo "set inf_initial_from_restart as false"
         set icyc = 1
      endif
    else
       echo ${OUTPUT_DIR}/${time_pre}/${INFL_OUT}_mean.nc does exist. copy them
       ${LINK} ${OUTPUT_DIR}/${time_pre}/${INFL_OUT}_mean.nc ${INFL_IN}_mean.nc
       ${LINK} ${OUTPUT_DIR}/${time_pre}/${INFL_OUT}_sd.nc   ${INFL_IN}_sd.nc
       set icyc = ${time_anl}
    endif
  endif
#
#
## disregard regional configuration for now
##
##set is_it_regional = `grep config_apply_lbcs ${NML_MPAS} | awk '{print $3}'`
##if ( $is_it_regional == true ) then
##    echo This script runs a regional mpas model.
### filename_template="lbc.$Y-$M-$D_$h.$m.$s.nc" => set fbdy = lbc.
##    set fbdy = `sed -n '/<immutable_stream name=\"lbc_in\"/,/\/>/{/Scree/{p;n};/##/{q};p}' ${STREAM_ATM} | \
##                grep filename_template | awk -F= '{print $2}' | awk -F$ '{print $1}' | sed -e 's/"//g'`
##    set flbc = `grep bdy_template_filename ${NML_DART} | awk '{print $3}' | cut -d ',' -f1 | sed -e "s/'//g" | sed -e 's/"//g'`
##    ${LINK} ${B_TEMPLATE} $flbc
##else
#    echo This script runs a global mpas model.
##endif
##chmod +x ./advance_model.tcsh
#
ls -1 ${NML_DART} || exit
#
  ${REMOVE} init.sed script*.sed
#
  if ( $ADAPTIVE_INF == true ) then       # For a spatially-varying prior inflation.
#
## inf_initial_from_restart => whether to read inflation files from input_{prior/post}inf_sd.nc
##  if inflation files are available at OUTPUT_DIR, set true
##  otherwise, set false to create this
    if ($icyc == 1) then
       cat >! script.sed << EOF
       /inf_initial_from_restart/c\
       inf_initial_from_restart    = .false.,                .false.,
       /inf_sd_initial_from_restart/c\
       inf_sd_initial_from_restart = .false.,                .false.,
EOF
    else
       cat >! script.sed << EOF
       /inf_initial_from_restart/c\
       inf_initial_from_restart    = .true.,                .true.,
       /inf_sd_initial_from_restart/c\
       inf_sd_initial_from_restart = .true.,                .true.,
EOF
    endif
#
  endif
#
  ${MOVE} ${NML_DART} ${NML_DART}.temp
  sed -f script.sed ${NML_DART}.temp >! ${NML_DART}             || exit 2
  ${REMOVE} script.sed ${NML_DART}.temp

#  #------------------------------------------------------
#  # 2. Update input files to get filter started 
#  # (assuming start_from_restart = .true. in input.nml)
#  #------------------------------------------------------
#  if USE_RESTART
  set frst = `sed -n '/<stream name=\"da_restart\"/,/\/>/{/Scree/{p;n};/##/{q};p}' ${RUN_DIR}/${STREAM_ATM} | \
              grep filename_template | awk -F= '{print $2}' | awk -F$ '{print $1}' | sed -e 's/"//g'`
# else (DA_STATE)

  set f_rst = ${frst}`echo ${anal_utc} | sed -e 's/:/\./g'`.nc     # bkg
  set f_anl = analysis.`echo ${f_rst} | cut -d . -f2-`             # dart anl
  set f_anlrst = afterda.`echo ${f_rst} | cut -d . -f2-`  # bkg updated with dart anl
#
  echo "Input ensemble for ${time_anl}"
  if( -e ${input_list})  ${REMOVE} ${input_list}
  if( -e ${output_list}) ${REMOVE} ${output_list}
  echo ${input_list} ${output_list}
  echo
#
  set i = 1
  while ( $i <= ${ENS_SIZE} )
    set i2 = `printf "%02d" $i` 
    set finput = ${OUTPUT_DIR}/${time_anl}/${ENS_DIR}${i2}/${f_rst}
    if (! -e ${finput}) then
      echo "Cannot find ${finput}."
      exit
    else
      echo ${finput} >> ${input_list}
      ${COPY} ${finput} ${OUTPUT_DIR}/${time_anl}/${ENS_DIR}${i2}/${f_anlrst}
      echo  ${OUTPUT_DIR}/${time_anl}/${ENS_DIR}${i2}/${f_anl} >> ${output_list}
      echo  ${OUTPUT_DIR}/${time_anl}/${ENS_DIR}${i2}/${f_anlrst} >> ${input_list}.state_update
    endif
    @ i++
  end

  tail -1 ${input_list}
  tail -1 ${output_list}
  tail -1 ${input_list}.state_update
#
  set ne = `cat ${input_list} | wc -l `
  if ( $ne != $ENS_SIZE ) then
     echo "We need ${ENS_SIZE} initial ensemble members, but found ${ne} only."
     exit
  endif
  echo
#
#  # change flag
#  #------------------------------------------------------
#  # 3. Obs sequence for this analysis cycle - one obs time at each analysis cycle
#  #------------------------------------------------------
  #set fn_obs = ${OBS_DIR}/obs_seq${time_anl} # without QC OBS
  set fn_obs = ${OBS_DIR}/obs_seq${time_anl}_after # after mpas_dart_obs_preprocess
  if ( ! -e ${fn_obs} ) then
     echo ${fn_obs} does not exist. Stop.
     exit
  endif
  ${LINK} ${fn_obs} ${obs_seq_in}
#
#
#  #------------------------------------------------------
#  # 4. Run filter
#  #------------------------------------------------------
   @ ncpu_filter = $FILTER_NODES * $N_PROCS_ANAL
   mpiexec -n ${ncpu_filter} ./filter                         #         for NCAR derecho
#
##  #------------------------------------------------------
##  # 5. Target time for model advance
##  #------------------------------------------------------
##  set greg_obs = `echo $time_anl ${INTV_DAY}d${INTV_SEC}s -g | ./advance_time`
##  set greg_obs_days = $greg_obs[1]
##  set greg_obs_secs = $greg_obs[2]
##  echo Target date: $time_nxt ${greg_obs_days}_${greg_obs_secs}
  ${COPY} ${NML_DART}    ${OUTPUT_DIR}/${time_anl}/${NML_DART}.filter
  ${COPY} ${obs_seq_out} ${OUTPUT_DIR}/${time_anl}

# check inflation files at time previous hour interval
  if ( $ADAPTIVE_INF == true ) then
    if ( ! -e ${INFL_OUT}_mean.nc ) then
      echo ${OUTPUT_DIR}/${time_pre}/${INFL_OUT}_mean.nc does not exist. check your exp!
      exit
    else   
       ${COPY} ${INFL_OUT}_mean.nc ${OUTPUT_DIR}/${time_anl}/${INFL_OUT}_mean.nc
       ${COPY} ${INFL_OUT}_sd.nc   ${OUTPUT_DIR}/${time_anl}/${INFL_OUT}_sd.nc
    endif
  endif
# log file
  ${COPY} dart_log.nml ${OUTPUT_DIR}/logs/${time_anl}/dart_log.nml.filter
  ${COPY} dart_log.out ${OUTPUT_DIR}/logs/${time_anl}/dart_log.out.filter
##
##  #------------------------------------------------------
##  # 6. Run update_mpas_states for all ensemble members
##  #------------------------------------------------------
 # We copied original BKG before update this.
   set fanal = `grep update_output_file_list input.nml | awk '{print $3}' | cut -d ',' -f1 | sed -e "s/'//g" | sed -e 's/"//g'`
   set nanal = `cat $fanal | wc -l`
 ##
   echo "REPLACE ${input_list} to update  mpas_state"
   ${COPY} ${input_list}.state_update ${input_list}

   ${LINK} ${RUN_DIR}/update_mpas_states                     .   || exit 1
   ./update_mpas_states >! update_mpas_states.${time_anl}.log
 
   set i_err = `grep ERROR update_mpas_states.${time_anl}.log | wc -l`
   if($nanal != $ENS_SIZE || ${i_err} > 0 ) then
      echo Error in update_mpas_states.${time_anl}.log
      exit
   endif
 
   mv update_mpas_states.${time_anl}.log ${OUTPUT_DIR}/logs/${time_anl}

##  #------------------------------------------------------
##  # 7. Run update_bc for all ensemble members (for regional MPAS)
##  #------------------------------------------------------
##  if ( $is_it_regional > 0 ) then
##
##  set anllist = `grep update_analysis_file_list input.nml | awk '{print $3}' | cut -d ',' -f1 | sed -e "s/'//g" | sed -e 's/"//g'`
##  if($anllist != $fanal) then
##     echo $anllist should be the same as $fanal for update_bc. Exit.
##     exit
##  endif
##  set bdylist = `grep update_boundary_file_list input.nml | awk '{print $3}' | cut -d ',' -f1 | sed -e "s/'//g" | sed -e 's/"//g'`
##  if( -e $bdylist) ${REMOVE} $bdylist
##  if( -e  bdynext) ${REMOVE}  bdynext
##
##  echo Creating $bdylist for update_bc now.
##  set n = 1
##  while ( $n <= $ENS_SIZE )
##    set lbc0 = ${fbdy}`echo ${time_anl} 0 -w | advance_time | sed -e "s/:/\./g"`.nc
##    set lbcN = ${fbdy}`echo ${time_nxt} 0 -w | advance_time | sed -e "s/:/\./g"`.nc
##    if( -e member$n/${lbc0} ) then
##        echo member$n/${lbc0} >> $bdylist
##        ${COPY} member$n/${lbc0} member$n/prior.${lbc0}
##    else
##        echo Cannot find member$n/${lbc0}.
##    endif
##    if( -e member$n/${lbcN} ) then
##        echo member$n/${lbcN} >> bdynext
##    else
##        echo We need LBCs for the next time, but cannot find member$n/${lbcN}.
##    endif
##    @ n++
##  end
##
##  set nbdy = `cat cat $bdylist | wc -l`
##  set nbdyN = `cat cat bdynext | wc -l`
##  if($nbdy != $ENS_SIZE || $nbdyN != $ENS_SIZE) then
##     echo Not enough LBC files for the regional MPAS run. Stop.
##     exit
##  endif
##
##  # need to check why time_nxt is required at update_bc 
##  ${DART_DIR}/update_bc >! logs/update_bc.${icyc}.log
##  set i_err = `grep ERROR  logs/update_bc.${icyc}.log | wc -l`
##  if( ${i_err} > 0 ) then
##     echo Error in logs/update_bc.${icyc}.log.
##     exit
##  endif
##
##  endif #( $is_it_regional > 0 ) then
##
##  #------------------------------------------------------
##  # 9. Store output files
##  #------------------------------------------------------
##  echo Saving output files for ${time_anl}.
##  ls -lrt >> ${sav_dir}/list
##  set fstat = `grep stages_to_write input.nml | awk -F= '{print $2}'`
##  set fs = `echo $fstat | sed -e 's/,/ /g' | sed -e "s/'//g"`
##
##  foreach f ( $fs ${obs_seq_out} )
##    ${MOVE} ${f}* ${sav_dir}/
##  end
##
##
sleep 3

if ( -e ${obs_seq_out} )  touch ${RUN_DIR}/filter_done

set end_time = `date  +%s`
@ length_time = $end_time - $start_time
echo "duration_secs = $length_time"

# <next few lines under version control, do not edit>
# $URL$
# $Revision$
# $Date$


