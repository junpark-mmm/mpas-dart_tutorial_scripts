#!/bin/tcsh
####################################################################################
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
#   driver_initial_ens.tcsh - driver shell script that 
#                            1) generates initial conditions for MPAS ensemble 
#                            from GFS or GEFS external grib2 files.
#                            2) run MPAS-A to create initial forecast ensemble
#                          - Job will submit individual members
#                            to a queuing system 
#                            (or run them sequentially).
#
# $1 : forecast start date : e.g., 2019041700
# $2 : init_forecast_length (hr): e.g., 336
# $3 : path of your params.tcsh
#
####################################################################################

if ( $#argv >= 3 ) then
   set idate          = ${1}
   set init_forecast_length = ${2}
   set fn_param       = `readlink -f ${3}`
else
   echo three arguments are required. Cannot proceed.
   echo \$\1: DATE \$\2: FCST_LENGTH_HR \$\3: param.tcsh
   echo date format is YYYYMMDDHH (e.g., 2019041700)
   exit
endif

if(! -e $fn_param ) then
   echo $fn_param does not exist. Cannot proceed.
   exit
endif

source $fn_param

if( ! -e $RUN_DIR ) mkdir -p $RUN_DIR
cd ${RUN_DIR}

   foreach fn ( advance_time filter )
      if ( ! -x $fn ) then
         echo ${COPY} ${EXE_DIR}/${fn} .
              ${COPY} ${EXE_DIR}/${fn} .
         if ( ! $status == 0 ) then
            echo ABORT\: We cannot find required executable dependency $fn.
            exit
         endif
      endif
   end

   foreach fn ( mpas_first_advance.tcsh prep_initial_ens_ic.tcsh )
      if ( ! -r $fn ) then
         echo ${COPY} ${CSH_DIR}/${fn} .
              ${COPY} ${CSH_DIR}/${fn} .
         if ( ! $status == 0 ) then
            echo ABORT\: We cannot find required script $fn.
            exit
         endif
       endif
   end

   if ( ${USE_REGIONAL} == "true" ) then
      foreach fn ( update_bc )
         if ( ! -x $fn ) then
            echo ${COPY} ${EXE_DIR}/${fn} .
                 ${COPY} ${EXE_DIR}/${fn} .
            if ( ! $status == 0 ) then
               echo ABORT\: We cannot find required executable dependency $fn.
               exit
            endif
         endif
      end

      foreach fn ( prep_ens_lbc.tcsh )
         if ( ! -r $fn ) then
            echo ${COPY} ${CSH_DIR}/${fn} .
                 ${COPY} ${CSH_DIR}/${fn} .
            if ( ! $status == 0 ) then
               echo ABORT\: We cannot find required script $fn.
               exit
            endif
         endif
      end
   endif

   if ( ! -d MPAS_RUN ) then
      if ( ! -d $MPAS_DIR ) then
         echo $MPAS_DIR does not exist. Stop.
         exit
      endif
      ${LINK} $MPAS_DIR MPAS_RUN
   endif

#  Check to see if MPAS and DART namelists exist.  If not, copy them from model source
   foreach fn ( ${NML_MPAS} ${NML_INIT} )
      if ( ! -r ${fn} ) then
         ${COPY} ${TEMPLATE_DIR}/${fn} .
      endif
      if ( ! $status == 0 ) then
         echo ABORT\: We cannot find required script $fn.
         exit
      endif
   end

   foreach fn ( ${STREAM_INIT} )
      if ( ! -r ${fn} || -z $fn ) then
         ${COPY} ${TEMPLATE_DIR}/${fn} .
      endif
      if ( ! $status == 0 ) then
         echo ABORT\: We cannot find required script $fn.
         exit
      endif
   end

   foreach fn ( ${STREAM_ATM} ) # support two types of streams
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

   if ( ! -r ${NML_DART} ) then
      ${COPY} ${TEMPLATE_DIR}/${NML_DART} .
      if ( ! $status == 0 ) then
         echo ABORT\: We cannot find required script $fn.
         exit
      endif
   endif

   if ( ! -x ungrib.exe ) then
      ${COPY} ${WPS_DIR}/ungrib.exe .
      ${COPY} ${WPS_DIR}/link_grib.csh .
      if ( ! $status == 0 ) then
         echo ABORT\: We cannot find required script $fn.
         exit
      endif
   endif

   if ( ! -r ${NML_WPS} ) then
      ${COPY} ${TEMPLATE_DIR}/${NML_WPS} .
      if ( ! $status == 0 ) then
         echo ABORT\: We cannot find required script $fn.
         exit
      endif
   endif

   if ( ! -r Vtable ) then
      ${COPY} ${WPS_DIR}/ungrib/Variable_Tables/${VTABLE} Vtable
      if ( ! $status == 0 ) then
         echo ABORT\: We cannot find required script $fn.
         exit
      endif
   endif

   foreach fn ( obs_seq1.out ${MPAS_GRID}.static.nc )
      if ( ! -f ${fn} ) then
         ${COPY} ${TEMPLATE_DIR}/${fn} .
      endif
      if ( ! $status == 0 ) then
         echo ABORT\: We cannot find required file $fn.
         exit
      endif
   end

   @ ndecomp = $MODEL_NODES * $N_PROCS

   set fgraph = ${MPAS_GRID}.graph.info.part.${ndecomp}
   if ( ! -e ${fgraph} ) then
       ${LINK} ${TEMPLATE_DIR}/${fgraph} ${fgraph}
       if(! -e ${fgraph}) then
          echo "Cannot find ${fgraph} for n_mpas * n_proc (= $MODEL_NODES * $N_PROCS)"
          exit
       endif
   endif

   mkdir -p ${OUTPUT_DIR}/logs/${idate}

# start loop for members for ensemble IC generation.
  if ( ${EXT_DATA_TYPE} == "GFS" ) then
      echo "when using GFS, a single job is required"
      echo "since filter will create ensemble ICs"
      set n = 0
  else if ( ${EXT_DATA_TYPE} == "GFSENS" ) then
      set n = 1
  endif

  while ( $n <= $ENS_SIZE )

   set num = `printf "%02d" $n` # two-digit integer like 01, 02, 03, ...
   set job_name = "make_mpasic.${num}"
   set jobn = `echo $job_name | cut -c1-15`  # Stupid cheyenne cannot show the full job name.
  
   if ( $RUN_IN_PBS == "yes" ) then  #  PBS queuing system
       # derecho

      echo "2i\"                                                                  >! prep_ic.sed
      echo "#==================================================================\" >> prep_ic.sed
      echo "#PBS -N ${job_name}\"                                                 >> prep_ic.sed
      echo "#PBS -j oe\"                                                          >> prep_ic.sed 
      echo "#PBS -o ${OUTPUT_DIR}/logs/${idate}/init_mpas_${num}.log\"            >> prep_ic.sed
      echo "#PBS -A ${PROJ_NUMBER}\"                                              >> prep_ic.sed
      echo "#PBS -q ${QUEUE_MPAS}\"                                               >> prep_ic.sed
      if ( ${QUEUE_MPAS} == "main" ) then
         echo "#PBS -l job_priority=${QUEUE_PRIORITY_MPAS}\"                      >> prep_ic.sed
      endif
      echo "#PBS -l walltime=${TIME_INIT}\"                                       >> prep_ic.sed
      echo "#PBS -l select=${MODEL_NODES}:ncpus=${N_CPUS}:mpiprocs=${N_PROCS}:mem=${MEM_MPAS}GB\" \
                                                                                  >> prep_ic.sed
      echo "#=================================================================="  >> prep_ic.sed
      echo 's%${1}%'"${num}%g"                                                    >> prep_ic.sed
      echo 's%${2}%'"${idate}%g"                                                  >> prep_ic.sed
      echo 's%${3}%'"${fn_param}%g"                                               >> prep_ic.sed

      sed -f prep_ic.sed ./prep_initial_ens_ic.tcsh >! prep_initial_ens_ic.pbs
      qsub prep_initial_ens_ic.pbs
      ${REMOVE}  prep_initial_ens_ic.pbs prep_ic.sed

  else

    ./prep_initial_ens_ic.tcsh $num $idate $fn_param >! ${OUTPUT_DIR}/logs/${idate}/init_mpas_${num}.log

  endif

  if ( ${EXT_DATA_TYPE} == "GFS" ) then
      break # no need to run multiple jobs in case of using GFS
  endif

  @ n++

  end

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
    echo IC generation for member $num on $idate is complete

  endif

  # if regional, create LBCs for initial BKG forecasts
  #
  if ( ${USE_REGIONAL} == "true" ) then

     # start loop for members for ensemble LBC generation.
     if ( ${EXT_DATA_TYPE} == "GFS" ) then
         echo "when using GFS, a single LBC job is required"
         echo "However, LBC from a single GFS is not desirable"
         set n = 0
	 stop
     else if ( ${EXT_DATA_TYPE} == "GFSENS" ) then
         set n = 1
     endif

     while ( $n <= $ENS_SIZE )

        set num = `printf "%02d" $n` # two-digit integer like 01, 02, 03, ...
        set job_name = "make_mpaslbc.${num}"
        set jobn = `echo $job_name | cut -c1-15`  # Stupid cheyenne cannot show the full job name.
  
        if ( $RUN_IN_PBS == "yes" ) then  #  PBS queuing system
         # derecho

      echo "2i\"                                                                  >! prep_lbc.sed
      echo "#==================================================================\" >> prep_lbc.sed
      echo "#PBS -N ${job_name}\"                                                 >> prep_lbc.sed
      echo "#PBS -j oe\"                                                          >> prep_lbc.sed 
      echo "#PBS -o ${OUTPUT_DIR}/logs/${idate}/init_lbc_mpas_${num}.log\"        >> prep_lbc.sed
      echo "#PBS -A ${PROJ_NUMBER}\"                                              >> prep_lbc.sed
      echo "#PBS -q ${QUEUE_MPAS}\"                                               >> prep_lbc.sed
      if ( ${QUEUE_MPAS} == "main" ) then
         echo "#PBS -l job_priority=${QUEUE_PRIORITY_MPAS}\"                      >> prep_lbc.sed
      endif
      echo "#PBS -l walltime=${TIME_INIT}\"                                       >> prep_lbc.sed
      echo "#PBS -l select=${MODEL_NODES}:ncpus=${N_CPUS}:mpiprocs=${N_PROCS}:mem=${MEM_MPAS}GB\" \
                                                                                  >> prep_lbc.sed
      echo "#=================================================================="  >> prep_lbc.sed
      echo 's%${1}%'"${num}%g"                                                    >> prep_lbc.sed
      echo 's%${2}%'"${idate}%g"                                                  >> prep_lbc.sed
      echo 's%${3}%'"${init_forecast_length}%g"                                   >> prep_lbc.sed
      echo 's%${4}%'"${fn_param}%g"                                               >> prep_lbc.sed

      sed -f prep_lbc.sed ./prep_ens_lbc.tcsh >! prep_ens_lbc.pbs
      qsub prep_ens_lbc.pbs
      ${REMOVE}  prep_initial_ens_ic.pbs prep_lbc.sed

    else

      ./prep_ens_lbc.tcsh $num $idate ${init_forecast_length} $fn_param >! ${OUTPUT_DIR}/logs/${idate}/init_lbc_mpas_${num}.log

    endif

    @ n++

    end

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
      echo LBC generation for member $num on $idate is complete

    endif

  endif

#
# start loop for members for forecasts
# create memmber directories at ${RUN_DIR}
# This will have depdency on pbslog_prep_ic in case of employing PBS scheduler
set n = 1
while ( $n <= $ENS_SIZE )

   set num = `printf "%02d" $n` # two-digit integer like 01, 02, 03, ...
   set job_name = "init_mpas.${num}"
   set jobn = `echo $job_name | cut -c1-15`  # Stupid cheyenne cannot show the full job name.

   if ( $RUN_IN_PBS == "yes" ) then  #  PBS queuing system
       # derecho

      echo "2i\"                                                                  >! advance.sed
      echo "#==================================================================\" >> advance.sed
      echo "#PBS -N ${job_name}\"                                                 >> advance.sed
      echo "#PBS -j oe\"                                                          >> advance.sed 
      echo "#PBS -o ${OUTPUT_DIR}/logs/${idate}/init_mpas_${num}.log\"            >> advance.sed
      echo "#PBS -A ${PROJ_NUMBER}\"                                              >> advance.sed
      echo "#PBS -q ${QUEUE_MPAS}\"                                               >> advance.sed
      if ( ${QUEUE_MPAS} == "main" ) then
         echo "#PBS -l job_priority=${QUEUE_PRIORITY_MPAS}\"                      >> advance.sed
      endif
      echo "#PBS -l walltime=${TIME_INIT}\"                                       >> advance.sed
      echo "#PBS -l select=${MODEL_NODES}:ncpus=${N_CPUS}:mpiprocs=${N_PROCS}:mem=${MEM_MPAS}GB\" \
                                                                                  >> advance.sed
      echo "#=================================================================="  >> advance.sed
      echo 's%${1}%'"${num}%g"                                                    >> advance.sed
      echo 's%${2}%'"${idate}%g"                                                  >> advance.sed
      echo 's%${3}%'"${init_forecast_length}%g"                                   >> advance.sed
      echo 's%${4}%'"${fn_param}%g"                                               >> advance.sed

      sed -f advance.sed ./mpas_first_advance.tcsh >! mpas_first_advance.pbs
    
      qsub mpas_first_advance.pbs
      ${REMOVE} mpas_first_advance.pbs advance.sed

      sleep 15

  else

    ./mpas_first_advance.tcsh $num $idate $init_forecast_length $fn_param >! ${OUTPUT_DIR}/logs/${idate}/init_mpas_${num}.log

  endif

  @ n++

end

