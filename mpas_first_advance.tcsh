#!/bin/tcsh
########################################################################
#
#   mpas_first_advance.tcsh 
#       : shell script that can be used to create an 
#         initial MPAS ensemble forecast from prep_initial_ens_ic.tcsh 
#         so the background forecasts are available for cycling
#       - Dec 2024: updated to support 'da_state/invariant' stream
#
########################################################################

  # input argument
  set ensemble_member = ${1}     #  ensemble member
  set idate           = ${2}     #  spinup_init_date
  set fcst_hour       = ${3}     #  fcst_hour
  set paramfile       = ${4}	 #  the parameter file with variables

  source $paramfile

  # create experimental directory
  set temp_dir = ${RUN_DIR}/${ENS_DIR}${ensemble_member}

  if ( -d ${temp_dir} )  ${REMOVE} ${temp_dir}
  mkdir -p ${temp_dir}
  cd ${temp_dir}

# Get the program and necessary files for the model
  set MPAS_ANCIL_DIR = ${RUN_DIR}/MPAS_RUN/src/core_atmosphere/physics/physics_wrf/files
  ${COPY} ${RUN_DIR}/input.nml                         .   || exit 1                    
  ${LINK} ${RUN_DIR}/MPAS_RUN/atmosphere_model         .   || exit 1
  ${LINK} ${RUN_DIR}/MPAS_RUN/stream_list*             .   || exit 1
  ${LINK} ${MPAS_ANCIL_DIR}/*                          .   || exit 1
  ${LINK} ${RUN_DIR}/advance_time                      .   || exit 1
  ${LINK} ${RUN_DIR}/*graph*                           .   || exit 1             

# copy IC files stored at ${INIT_DIR}
   set ic_file = ${MPAS_GRID}.init.nc
   if ( ! -e ${ic_file} ) then
       ${COPY} ${INIT_DIR}/${idate}/${ENS_DIR}${ensemble_member}/${ic_file} ${ic_file}
       if(! -e ${ic_file}) then
          echo "Cannot find ${ic_file} from ${INIT_DIR}"
          exit
       endif
   endif

#  Determine the initial, final and run times for the MPAS integration
  set curr_yyyy = `echo $idate | cut -c1-4` 
  set curr_mm   = `echo $idate | cut -c5-6` 
  set curr_dd   = `echo $idate | cut -c7-8` 
  set curr_hh   = `echo $idate | cut -c9-10` 
  set curr_utc  = ${curr_yyyy}-${curr_mm}-${curr_dd}_${curr_hh}:00:00
  set targ_utc  = `echo ${curr_utc} +${fcst_hour}h -w | ./advance_time`

  set targ_yyyy = `echo ${targ_utc} | cut -c1-4`
  set targ_mm = `echo ${targ_utc} | cut -c6-7`
  set targ_dd = `echo ${targ_utc} | cut -c9-10`
  set targ_hh = `echo ${targ_utc} | cut -c12-13`

  set fdays = 0
  set fhours = $fcst_hour
  while ( $fhours >= 24 )
     @ fdays++
     @ fhours = $fhours - 24
  end
  set intv_utc = `echo $fdays + 100 | bc | cut -b2-3`_`echo $fhours + 100 | bc | cut -b2-3`:00:00

#  Update namelist.atmosphere
  # IF REGIONAL
  set FLAG_REGIONAL  = false 
  # Initial Spinup FCST
  set FLAG_RESTART   = false
  set FLAG_DACYCLING = false

  if ( $USE_RESTART == "true" ) then  #  PBS queuing system
  # use traditional 'restart' stream
     set FLAG_JEDI_DA     = false
  else
  # use 'da_state' + 'invariant' stream
     set FLAG_JEDI_DA      = true
  endif

  #  Generate MPAS namelist file
  cat >! script.sed << EOF
  /config_start_time/c\
  config_start_time = '$curr_utc'
  /config_run_duration/c\
  config_run_duration = '$intv_utc'
  /config_apply_lbcs/c\
  config_apply_lbcs = ${FLAG_REGIONAL}
  /config_do_restart/c\
  config_do_restart = ${FLAG_RESTART}
  /config_do_DAcycling/c\
  config_do_DAcycling = ${FLAG_DACYCLING}
  /config_block_decomp_file_prefix/c\
  config_block_decomp_file_prefix= '${MPAS_GRID}.graph.info.part.'
  /config_dt/c\
  config_dt = ${DT_MPAS}
  /config_jedi_da/c\
  config_jedi_da = ${FLAG_JEDI_DA}
EOF

  if ( $USE_LEN_DISP == "true" ) then
  cat >> script.sed << EOF
/&nhyd_model/a \
  config_len_disp = ${LEN_DISP}
EOF
  endif

  sed -f script.sed ${RUN_DIR}/${NML_MPAS} >! ${NML_MPAS}

cat >! sst.sed << EOF
   /config_sst_update /c\
    config_sst_update = ${SST_UPDATE}
EOF
mv $NML_MPAS namelist.sst
sed -f sst.sed namelist.sst >! $NML_MPAS

if ( $SST_UPDATE == true ) then
  set fsst = `sed -n '/<stream name=\"surface\"/,/\/>/{/Scree/{p;n};/##/{q};p}' ${STREAM_ATM} | \
              grep filename_template | awk -F= '{print $2}' | awk -F$ '{print $1}' | sed -e 's/"//g'`
  ${LINK} ${SST_DIR}/${SST_FNAME} $fsst         || exit
else
  echo NO SST_UPDATE...
endif

  # clean out any old rsl files if exist
  if ( -e log.0000.out ) ${REMOVE} log.*

  if ( $USE_RESTART == "true" ) then  #  PBS queuing system

  cat >! streams.sed << EOF
/<immutable_stream name="input"/,/<\/*immutable_stream>/ {
s/filename_template="init.nc"/filename_template="${ic_file}"/ }
EOF

  else
      # link IC file as invariant file here
      set invariant_file = ${MPAS_GRID}.invariant.nc

      ln -sf ${ic_file} ${invariant_file}

  cat >! streams.sed << EOF
/<immutable_stream name="invariant"/,/<\/*immutable_stream>/ {
s/filename_template="init.nc"/filename_template="${invariant_file}"/ }
/<immutable_stream name="input"/,/<\/*immutable_stream>/ {
s/filename_template="afterda_mpasout.nc"/filename_template="${ic_file}"/ }
EOF

  endif

  sed -f streams.sed ${RUN_DIR}/${STREAM_ATM}  >! ${STREAM_ATM}

  #  Run MPAS for the specified amount of time 
  @ ndecomp = $MODEL_NODES * $N_PROCS
  mpiexec -n ${ndecomp}  ./atmosphere_model   || exit 3
#
#  # Check the output file
  if ( $USE_RESTART == "true" ) then  #  PBS queuing system
  # use traditional 'restart' stream
  # split line to reduce length
     set frst = `sed -n '/<stream name=\"da_restart\"/,/\/>/{/Scree/{p;n};/##/{q};p}' \
                 ${STREAM_ATM} | \
                 grep filename_template | awk -F= '{print $2}' | awk -F$ '{print $1}' | \
                 sed -e 's/"//g'`
  else
  # use 'da_state' + 'invariant' stream
  # to do
     set frst = `sed -n '/<immutable_stream name=\"da_state\"/,/\/>/{/Scree/{p;n};/##/{q};p}' \
                 ${STREAM_ATM} | \
                 grep filename_template | awk -F= '{print $2}' | awk -F$ '{print $1}' | \
                 sed -e 's/"//g'`
  endif

#
  set fout = ${frst}`echo ${targ_utc} | sed -e 's/:/\./g'`.nc

# copy data to ${OUTPUT_DIR}
  set target_dir = ${OUTPUT_DIR}/${targ_yyyy}${targ_mm}${targ_dd}${targ_hh}/${ENS_DIR}${ensemble_member}

  if ( -d ${target_dir} )  ${REMOVE} ${target_dir}
  mkdir -p ${target_dir}

  ${COPY} -r ${fout} ${target_dir}
  ${COPY} -r log.atmosphere.0000.out ${OUTPUT_DIR}/logs/${idate}/spinup_fcst${ensemble_member}.${idate}.f${fcst_hour}.out
# 
  foreach rfile ( `ls -1 mpasout.*.nc history.*.nc restart.*.nc diag.*.nc` )
    if ( $rfile != $fout )  ${REMOVE} $rfile
  end
# 
