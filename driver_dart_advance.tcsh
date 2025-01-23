#!/bin/tcsh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
##############################################################################################
#  driver_mpas_dart.tcsh
#
#  THIS IS A TOP-LEVEL DRIVER SCRIPT FOR CYCLING RUNS. 
#  BOTH THE ENSEMBLE KALMAN FILTER AND THE MPAS FORECAST ARE RUN IN MPI.
#
#  This is a sample script for cycling runs in a retrospective case study, 
#  and was tested on the NCAR IBM Supercomputer (cheyenne) using a "qsub" command.
#
#  Note:
#  1. For the general configuration including all the file names, edit setup.csh.
#  2. For the model configuration, our general policy is that we only edit the parameters that
#     affect the I/O stream here and leave all the rest unchanged (ex. physics options). 
#     This means that it is the user's responsibility to edit all other namelist parameters 
#     before running this script. One exception is the time info, which will be updated inside 
#     advance_model.csh for each cycle.
#  3. This script does NOT specify all the options available for the EnKF data assimilation either.
#     For your own complete filter design, you need to edit your input.nml
#     - at least &filter_nml, &obs_kind_nml, &model_nml, &location_nml and &mpas_vars_nml sections 
#     to set up your filter configuration before running this script.
#  4. For adaptive inflation, we only support the choice of prior adaptive inflation in the state
#     space here. For more options, check DART/assimilation_code/modules/assimilation/filter_mod.html.
#  5. All the logical parameters are case-sensitive. They should be either true or false.
#  6. We no longer support the hpss storage in NCAR supercomputers.
#     And all the output files will be locally stored. 
#     For a large ensemble run, check if you have enough disk space before running this script.
#
#  Required scripts to run this driver:
#  (All the template files are available in either shell_scripts or data under DART/models/mpas_atm/.)
#  1. setup.csh                  (for the general configuration of this experiment)
#  2. namelist.atmosphere        (for mpas)   - a namelist template for mpas.
#  3. input.nml                  (for filter) - a namelist template for filter. 
#  4. filter.template.pbs        (for an mpi filter run; with async >= 2)
#  5. advance_model.template     (for an mpi mpas run; using separate nodes for each ensemble member)
#  6. advance_model.csh          (for mpas/filter) - a driver script to run mpas forecast at each cycle
#
#  Input files to run this script:
#  A. input_state_file_list  - a list of input ensemble netcdf files for DART/filter
#  B. output_state_file_list - a list of output ensemble netcdf files from DART/filter
#  C. RUN_DIR/member#/${mpas_filename}    - the input file listed in input_state_file_list for each member
#  D. OBS_DIR/${obs_seq_in}.${YYYYMMDDHH} - obs sequence files for each analysis cycle (YYYYMMDDHH) 
#     for the entire period.
# 
#  Written by Soyoung Ha (MMM/NCAR)
#  Updated and tested on yellowstone (Feb-20-2013)
#  Updated for MPAS V5 and DART/Manhattan; tested on cheyenne (Jun-27-2017)
#  Updated for a better streamline and consistency: Ryan Torn (Jul-6-2017)
#  Updated for MPASV7: Soyoung Ha (Mar-4-2020)
#
#  For any questions or comments, contact: syha@ucar.edu (+1-303-497-2601)
##############################################################################################
# USER SPECIFIED PARAMETERS
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
#------------------------------------------
# Check if we have all the necessary files.
#------------------------------------------

set  FILELIST = ( assimilate.tcsh mpas_advance.tcsh )
foreach fn ( ${FILELIST} )
   if ( ! -r $fn || -z $fn ) then
      echo ${COPY} ${CSH_DIR}/${fn} .
           ${COPY} ${CSH_DIR}/${fn} .
      if( ! $status == 0 ) then
         echo ABORT\: We cannot find required script $fn
         exit
      endif
   endif
end

# FILELIST
#set FILELIST = (filter advance_time update_mpas_states update_bc)
set  FILELIST = ( filter advance_time update_mpas_states )
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

if ( ! -d MPAS_RUN ) then

   if ( ! -d $MPAS_DIR ) then
      echo $MPAS_DIR does not exist. Stop.
      exit
   endif
   ${LINK} $MPAS_DIR MPAS_RUN

endif

#  Check to see if MPAS and DART namelists exist. If not, copy them from template
   foreach fn ( ${NML_MPAS} ${NML_DART} )
      if ( ! -r ${fn} ) then
         ${COPY} ${TEMPLATE_DIR}/${fn} .
      endif
      if ( ! $status == 0 ) then
         echo ABORT\: We cannot find required script $fn.
         exit
      endif
   end

   foreach fn ( ${STREAM_ATM} )
      if ( ! -r ${fn} || -z $fn ) then
         if ( $USE_RESTART == "true" ) then
             ${COPY} ${TEMPLATE_DIR}/${fn} .
         else
             ${COPY} ${TEMPLATE_DIR}/${fn}.new ${fn}
         endif
      endif
      if ( ! $status == 0 ) then
         echo ABORT\: We cannot find required script $fn.
         exit
      endif
   end

   #foreach fn ( ${MPAS_GRID}.static.nc )
   #   if ( ! -f ${fn} ) then
   #      ${COPY} ${TEMPLATE_DIR}/${fn} .
   #   endif
   #   if ( ! $status == 0 ) then
   #      echo ABORT\: We cannot find required file $fn.
   #      exit
   #   endif
   #end

   @ ndecomp = $MODEL_NODES * $N_PROCS

   set fgraph = ${MPAS_GRID}.graph.info.part.${ndecomp}
   if ( ! -e ${fgraph} ) then
       ${LINK} ${TEMPLATE_DIR}/${fgraph} ${fgraph}
       if(! -e ${fgraph}) then
          echo "Cannot find ${fgraph} for n_mpas * n_proc (= $MODEL_NODES * $N_PROCS)"
          exit
       endif
   endif

#------------------------------------------
# Time info
#------------------------------------------
# sdate - greg_beg
# edate - greg_end
# intv_second -> intv_hr

set DATE_BEG = `echo "${sdate} 0 -w"| ./advance_time` #"${syyyy}-${smm}-${sdd}_${shh}:00:00"
set DATE_END = `echo "${edate} 0 -w"| ./advance_time` #"${eyyyy}-${emm}-${edd}_${ehh}:00:00"

set intv_second = `expr ${interval_hour} \* 3600`
set greg_beg = `echo $DATE_BEG 0 -g | ./advance_time`
set greg_end = `echo $DATE_END 0 -g | ./advance_time`
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

echo Running at $RUN_DIR
echo " "

#------------------------------------------
# Initial ensemble for $DATE_INI
#------------------------------------------
# check if data are available from driver_initial_ens.tcsh

#--------------------------------------------------------
# Cycling gets started
#--------------------------------------------------------

# update logic - time_anl will be updated ${intv_hr}
set time_anl = ${sdate}
set time_end = ${edate}
#
## Can you time info based on DATE or advance_time function.
while ( $time_anl <= $time_end )
#
  set time_pre = `echo $time_anl -$intv_hr | ./advance_time`	#YYYYMMDDHH
  set time_nxt = `echo $time_anl +$intv_hr | ./advance_time`	#YYYYMMDDHH
  set anal_utc = `echo $time_anl 0 -w | ./advance_time`
  set greg_obs = `echo $time_anl 0 -g | ./advance_time`
  set greg_obs_days = $greg_obs[1]
  set greg_obs_secs = $greg_obs[2]

  echo Cycle at ${time_anl}\: ${greg_obs_days}_${greg_obs_secs}
#
  set sav_dir = ${OUTPUT_DIR}/${time_anl}
  mkdir -p ${sav_dir}
  mkdir -p ${OUTPUT_DIR}/logs/${time_anl}

#------------------------------------------------------
# 4. Run filter
#------------------------------------------------------
  set job_name = "filter.${time_anl}"
  set jobn = `echo $job_name | cut -c1-15`  # Stupid cheyenne cannot show the full job name.
  echo Running filter: $job_name
#
  if ( $RUN_IN_PBS == yes ) then

       # derecho
      echo "2i\"                                                                  >! filter.sed
      echo "#==================================================================\" >> filter.sed
      echo "#PBS -N ${job_name}\"                                                 >> filter.sed
      echo "#PBS -j oe\"                                                          >> filter.sed 
      echo "#PBS -o ${OUTPUT_DIR}/logs/${time_anl}/${job_name}.log\"              >> filter.sed
      echo "#PBS -A ${PROJ_NUMBER}\"                                              >> filter.sed
      echo "#PBS -q ${QUEUE_FILTER}\"                                             >> filter.sed
      if ( ${QUEUE_FILTER} == "main" ) then
         echo "#PBS -l job_priority=${QUEUE_PRIORITY_FILTER}\"                    >> filter.sed
      endif
      echo "#PBS -l walltime=${TIME_FILTER}\"                                     >> filter.sed
      echo "#PBS -l select=${FILTER_NODES}:ncpus=${N_CPUS}:mpiprocs=${N_PROCS_ANAL}:mem=${MEM_FILTER}GB\" \
                                                                                  >> filter.sed
      echo "#=================================================================="  >> filter.sed
      echo 's%${1}%'"${time_anl}%g"                                               >> filter.sed 
      echo 's%${2}%'"${intv_second}%g"                                            >> filter.sed
      echo 's%${3}%'"${fn_param}%g"                                               >> filter.sed

    sed -f filter.sed assimilate.tcsh >! assimilate.pbs
    qsub assimilate.pbs
    sleep 60
    #${REMOVE} filter.sed assimilate.pbs
#
#    # Wait until the job is finished.
    set is_there = `qstat | grep $jobn | wc -l`
    while ( $is_there != 0 )
      sleep 30
      set is_there = `qstat | grep $jobn | wc -l`
    end
#
  else
#
      ./assimilate.tcsh ${time_anl} ${intv_second} ${fn_param} >! ${OUTPUT_DIR}/logs/${time_anl}/${job_name}.log 
#
  endif
#
#  # Check errors in filter.
  if ( -e filter_started && ! -e filter_done ) then
    echo "Filter was not normally finished. Exiting."
    ${REMOVE} filter_started
    exit
  endif
#
  ${REMOVE} filter_started filter_done
  echo Filter is done for Cycle at ${time_anl}
#
#  #------------------------------------------------------
#  # 8. Advance model for each member
#  #------------------------------------------------------
#  # Run forecast for ensemble members until the next analysis time
#  echo Advance models for ${ENS_SIZE} members now...
#
#  if( -e list.${time_nxt}.txt ) \rm -f list.${time_nxt}.txt
#
  set n = 1
  while ( $n <= $ENS_SIZE )
#
   set num = `printf "%02d" $n` # two-digit integer like 01, 02, 03, ...
   set job_ensemble = ${EXPERIMENT_NAME}.advance.e${num}
   set jobn = `echo $job_ensemble | cut -c1-8`

   if ( $RUN_IN_PBS == "yes" ) then  #  PBS queuing system
       # derecho

      echo "2i\"                                                                  >! advance.sed
      echo "#==================================================================\" >> advance.sed
      echo "#PBS -N ${job_ensemble}\"                                             >> advance.sed
      echo "#PBS -j oe\"                                                          >> advance.sed 
      echo "#PBS -o ${OUTPUT_DIR}/logs/${time_anl}/mpas_advance.e${num}.log\"     >> advance.sed
      echo "#PBS -A ${PROJ_NUMBER}\"                                              >> advance.sed
      echo "#PBS -q ${QUEUE_MPAS}\"                                               >> advance.sed
      if ( ${QUEUE_MPAS} == "main" ) then
         echo "#PBS -l job_priority=${QUEUE_PRIORITY_MPAS}\"                      >> advance.sed
      endif
      echo "#PBS -l walltime=${TIME_MPAS}\"                                       >> advance.sed
      echo "#PBS -l select=${MODEL_NODES}:ncpus=${N_CPUS}:mpiprocs=${N_PROCS}:mem=${MEM_MPAS}GB\" \
                                                                                  >> advance.sed
      echo "#=================================================================="  >> advance.sed
      echo 's%${1}%'"${num}%g"                                                    >> advance.sed
      echo 's%${2}%'"${time_anl}%g"                                               >> advance.sed
      echo 's%${3}%'"${intv_hr}%g"                                                >> advance.sed
      echo 's%${4}%'"${fn_param}%g"                                               >> advance.sed

      sed -f advance.sed ./mpas_advance.tcsh >! mpas_advance.pbs
      qsub mpas_advance.pbs
      sleep 5

    else

      ./mpas_advance.tcsh $num $time_anl $intv_hr $fn_param >! ${OUTPUT_DIR}/logs/${time_anl}/${job_ensemble}.log 
    endif

    @ n++
  
  end
#
  if ( $RUN_IN_PBS == yes ) then
    sleep 60

    # Check if all members are done advancing model.
    set is_all_done = `qstat | grep ${jobn} | wc -l`
    while ( $is_all_done > 0 )
      sleep 30
      set is_all_done = `qstat | grep ${jobn} | wc -l`
    end
    date
    sleep 30

  endif
#
#  #------------------------------------------------------
#  # 10. Get ready to run filter for next cycle.
#  #------------------------------------------------------
#  cd $RUN_DIR
#  ls -lL list.${time_nxt}.txt		|| exit
#
#  set f_fcst = `head -1 list.${time_nxt}.txt`
#  set   fout = `basename ${f_fcst}`
#  set   nout = `cat list.${time_nxt}.txt | wc -l`
#
#  if ( $nout != ${ENS_SIZE} ) then
#  set n = 1
#  while ( $n <= ${ENS_SIZE} )
#    if( ! -e ${ENS_DIR}${n}/${fout} ) then
#      echo Missing ${ENS_DIR}${n}/${fout}
#      echo ${ENS_DIR}${n}/${fout} >> missing.${time_nxt}.txt
#    endif
#    @ n++
#  end
#  endif #( $nout != ${ENS_SIZE} ) then
#
#  if( -e missing.${time_nxt}.txt ) then
#     echo This cycle is incomplete. Check missing members.
#     cat missing.${time_nxt}.txt
#     exit
#  else
#     echo Filter is ready to go for $nout members for the next cycle now.
#     head -1 ${input_list}
#     set time_anl = $time_nxt
#     @ icyc++
#  endif
#
  set time_anl = ${time_nxt}
end
#
#echo Cycling is done for $n_cycles cycles in ${EXPERIMENT_NAME}.
#echo Script exiting normally.
#
exit 0
