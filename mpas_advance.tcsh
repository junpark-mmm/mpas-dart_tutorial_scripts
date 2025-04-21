#!/bin/tcsh
########################################################################
#
#   mpas_advance.tcsh 
#       : shell script that can be used to run short 
#         MPAS-A ensemble forecast from DA analyses
#         for cycling DA
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

  if ( ${USE_REGIONAL} == "true" ) then
     ${LINK} ${RUN_DIR}/update_bc                      .   || exit 1
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

# copy IC files stored at ${OUTPUT_DIR}
   set ic_file = ${MPAS_GRID}.afterda.nc
   if ( ! -e ${ic_file} ) then
       set frst_input = afterda.`echo ${curr_utc} | sed -e 's/:/\./g'`.nc
       ${COPY} ${OUTPUT_DIR}/${idate}/${ENS_DIR}${ensemble_member}/${frst_input} ${ic_file}
       if(! -e ${ic_file}) then
          echo "Cannot find ${ic_file} from ${OUTPUT_DIR}/${idate}/${ENS_DIR}${ensemble_member}"
          exit
       endif
       # if using invariant and da_state
       if ( $USE_RESTART == "false" ) then  # also copy invariant file = IC file used for initial forecast
           set init_file = `ls -1 ${INIT_DIR}/*/${ENS_DIR}${ensemble_member}/${MPAS_GRID}.init.nc | head -1`
           set invariant_file = ${MPAS_GRID}.invariant.nc
           ${LINK} ${init_file} ${invariant_file}
           if(! -e ${invariant_file}) then
              echo "Cannot find ${invariant_file} from ${INIT_DIR}/*/${ENS_DIR}${ensemble_member}"
           endif
       endif
   endif

  if ( ${USE_REGIONAL} == "true" ) then
# to do: check if LBC files exist and then copy
    set count_lbc = `ls -1 ${INIT_DIR}/${idate}/${ENS_DIR}${ensemble_member}/lbc* | wc | awk '{ print $1}'`
    if ( ${count_lbc} >= 1 ) then 
       ${LINK} ${INIT_DIR}/${idate}/${ENS_DIR}${ensemble_member}/lbc* .
    else
       echo "Cannot find lbc files from ${INIT_DIR}"
       exit
    endif

    # tutorial domain (~ 60 km) may be not require hydrometeor LBCs
    #set LBC_VARS = "lbc_qv, lbc_theta, lbc_rho, lbc_u"
    #set lbc_update_from_reconstructed_winds = ".false." # obsolete
    #set lbc_update_winds_from_increments    = ".false." # obsolete
    
    ls -1 ${ic_file} > filter_in.txt
    set first_lbc_file = `ls -1 lbc*.nc | head -1`
    ${REMOVE} ${first_lbc_file}
    ${COPY} ${INIT_DIR}/${idate}/${ENS_DIR}${ensemble_member}/${first_lbc_file} .

    if ( $USE_RESTART == "false" ) then  # also copy invariant file = IC file used for initial forecast
        ln -sf ${invariant_file} init.nc
    else
        ln -sf ${ic_file} init.nc
    endif

    ls -1 ${first_lbc_file} > boundary_inout.txt

    cat >! update_bc.sed << EOF
    /mpas_lbc_variables/c\
    mpas_lbc_variables = ${LBC_VARS}
EOF

    ${MOVE} ${NML_DART} ${NML_DART}.temp
    sed -f update_bc.sed ${NML_DART}.temp >! ${NML_DART}             || exit 2
    ${REMOVE} script.sed ${NML_DART}.temp

    ./update_bc
    echo "Updated LBC using update_bc in MPAS-DART"

  endif

#  Update namelist.atmosphere
  # FCST during DA cycling
  set FLAG_DACYCLING = true

  if ( $USE_RESTART == "true" ) then
  # use traditional 'restart' stream
     set FLAG_JEDI_DA   = false
     set FLAG_RESTART   = true
  else
  # use 'da_state' + 'invariant' stream
     set FLAG_JEDI_DA      = true
     set FLAG_RESTART     = false
  endif

  #  Generate MPAS namelist file
  cat >! script.sed << EOF
  /config_start_time/c\
  config_start_time = '$curr_utc'
  /config_run_duration/c\
  config_run_duration = '$intv_utc'
  /config_apply_lbcs/c\
  config_apply_lbcs = ${USE_REGIONAL}
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

  # clean out any old rsl files if exist
  if ( -e log.0000.out ) ${REMOVE} log.*

  if ( $USE_RESTART == "true" ) then

  cat >! streams.sed << EOF
/<immutable_stream name="restart"/,/<\/*immutable_stream>/ {
s/filename_template="afterda_restart.nc"/filename_template="${ic_file}"/ }     
EOF

  else

  cat >! streams.sed << EOF
/<immutable_stream name="invariant"/,/<\/*immutable_stream>/ {
s/filename_template="init.nc"/filename_template="${invariant_file}"/ }
/<immutable_stream name="input"/,/<\/*immutable_stream>/ {
s/filename_template="afterda_mpasout.nc"/filename_template="${ic_file}"/ }
EOF

  endif

    # The script is tested with 6-hourly update of SST
  # if you want to change the interval, modify the below hard-coded value
  if ( $SST_UPDATE == true ) then
  set SST_UPDATE_SECONDS = 21600
  cat >> streams.sed << EOF
/<stream name="surface"/,/<\/stream>/ {
s/input_interval="none"/input_interval="${SST_UPDATE_SECONDS}"/ }
EOF
  endif

  sed -f streams.sed ${RUN_DIR}/${STREAM_ATM}  >! ${STREAM_ATM}

if ( $SST_UPDATE == true ) then
  set fsst = `sed -n '/<stream name=\"surface\"/,/\/>/{/Scree/{p;n};/##/{q};p}' ${STREAM_ATM} | \
              grep filename_template | awk -F= '{print $2}' | awk -F$ '{print $1}' | sed -e 's/"//g'`
  ${LINK} ${SST_DIR}/${SST_FNAME} $fsst         || exit
else
  echo "NO SST_UPDATE..."
endif

  #  Run MPAS for the specified amount of time 

  @ ndecomp = $MODEL_NODES * $N_PROCS
  mpiexec -n ${ndecomp} ./atmosphere_model   || exit 3
#
#  # Check the output file
  if ( $USE_RESTART == "true" ) then
  # use traditional 'restart' stream
     set frst = `sed -n '/<stream name=\"da_restart\"/,/\/>/{/Scree/{p;n};/##/{q};p}' ${STREAM_ATM} | \
                 grep filename_template | awk -F= '{print $2}' | awk -F$ '{print $1}' | sed -e 's/"//g'`
  else
  # use 'da_state' + 'invariant' stream
  # to do
     set frst = `sed -n '/<immutable_stream name=\"da_state\"/,/\/>/{/Scree/{p;n};/##/{q};p}' ${STREAM_ATM} | \
                 grep filename_template | awk -F= '{print $2}' | awk -F$ '{print $1}' | sed -e 's/"//g'`
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
  if ( $USE_REGIONAL == "true" ) then  #  PBS queuing system
     set ncfilelist=`ls -1 mpasout.*.nc history.*.nc restart.*.nc diag.*.nc lbc.*.nc ` 
  else
     set ncfilelist=`ls -1 mpasout.*.nc history.*.nc restart.*.nc diag.*.nc `
  endif 

  foreach rfile ( ${ncfilelist} )
    if ( $rfile != $fout )  ${REMOVE} $rfile
  end
# 
