#!/bin/tcsh
######################################################################## #
#   prep_ens_lbc.tcsh - shell script that can be used to create an 
#                        initial MPAS ensemble from an external grib
#                         file, two options are available.
#
# Output  : ${INIT_DIR}/member${XX}/lbc_${DATE}.nc
#
########################################################################

  set ensemble_member = ${1}
  set idate           = ${2}
  set forecast_length = ${3}
  set paramfile       = ${4}

  source $paramfile

  set icfile = ${INIT_DIR}/*/${ENS_DIR}${ensemble_member}/${MPAS_GRID}.init.nc
  
  foreach fn ( ${icfile} )
     if ( ! -r ${fn} ) then
        echo ABORT\: prep_ens_lbc.tcsh could not find required readable dependency ${fn}
        exit 1
     endif
  end

# for GFS, use 00 for ensemble member
#
  set temp_dir = ${RUN_DIR}/${ENS_DIR}${ensemble_member}
  set target_dir = ${INIT_DIR}/${idate}/${ENS_DIR}${ensemble_member}
#
  if ( -d ${temp_dir} )  ${REMOVE} ${temp_dir}
  mkdir -p ${temp_dir}
  mkdir -p ${target_dir}
  cd ${temp_dir}
#
#  Get the program and necessary files for the model
  ${LINK} ${RUN_DIR}/ungrib.exe                        .   || exit 1
  ${LINK} ${RUN_DIR}/link_grib.csh                     .   || exit 1
  ${LINK} ${RUN_DIR}/advance_time                      .   || exit 1
  ${LINK} ${RUN_DIR}/MPAS_RUN/init_atmosphere_model    .   || exit 1
  ${LINK} ${RUN_DIR}/*graph*                           .   || exit 1             
  ${LINK} ${RUN_DIR}/Vtable                            .   || exit 1
  ${COPY} ${RUN_DIR}/input.nml                         .   || exit 1

#  Determine the initial time for the MPAS initialization
  set curr_yyyy = `echo $idate | cut -c1-4` 
  set curr_mm   = `echo $idate | cut -c5-6` 
  set curr_dd   = `echo $idate | cut -c7-8` 
  set curr_hh   = `echo $idate | cut -c9-10` 
  set curr_utc  = ${curr_yyyy}-${curr_mm}-${curr_dd}_${curr_hh}:00:00

  set cdate = ${idate}
  set edate = `echo "${idate} ${forecast_length}"| ./advance_time` #yyyymmddhh
  set end_utc = `echo "${idate} ${forecast_length} -w"| ./advance_time`

  # Link grib file, run WPS ungrib program to convert into format that MPAS can use
  # for global
  # GFS or GFSENS
  # Add loop using idate and forecast length
  # if you want to use FCST of external data, comment below variable and then add to 'params.tcsh'
  set USE_FCST_FROM_EXTERNAL_DATA = false

  if ( ${USE_FCST_FROM_EXTERNAL_DATA} == "true" ) then # assumes that a single directory has all the fcst grib2
      if ( ${EXT_DATA_TYPE} == "GFS" ) then
          ${LINK} ${EXTM_DIR}/${idate}/gfs* .
          ./link_grib.csh gfs*
      else if ( ${EXT_DATA_TYPE} == "GFSENS" ) then
          ${LINK} ${EXTM_DIR}/${ensemble_member}/${idate}/gep${ensemble_member}.t${curr_hh}z.* .
          ./link_grib.csh gep${ensemble_member}*
      endif
  else # use externaly data only at analysis time ; assumes that each directory has a single analyis grib2 file
           ${REMOVE} grib2f_*
           while ( ${cdate} <= ${edate} ) 
               if ( ${EXT_DATA_TYPE} == "GFS" ) then
                  ${LINK} ${EXTM_DIR}/${cdate}/gfs*f000* grib2f_${cdate}
               else if ( ${EXT_DATA_TYPE} == "GFSENS" ) then
                  ${LINK} ${EXTM_DIR}/${ensemble_member}/${cdate}/gep${ensemble_member}*f000* grib2f_${cdate}
               endif
	       set cdate_base = ${cdate}
               set cdate = `echo "${cdate_base} 6"| ./advance_time` #yyyymmddhh
           end
          ./link_grib.csh grib2f_*
  endif
#
  cat >! script.sed << EOF
  /start_date/c\
  start_date = '${curr_utc}',
  /end_date/c\
  end_date   = '${end_utc}',
  /prefix/c\
  prefix   = 'FILE',
EOF

  sed -f script.sed ${RUN_DIR}/namelist.wps >! namelist.wps
#
  ./ungrib.exe >& ungrib.out
#
#  create namelist file for init version of MPAS
#  1. LBC need to set 'config_init_case' as 9
#  2. assumes 6-hour intervals for template files 
#     if need changes, adjust this
  set CONFIG_FG_INTERVAL = 21600 # seconds

  cat >! script.sed << EOF
  /config_init_case/c\
  config_init_case = 9
  /config_fg_interval/c\
  config_fg_interval = ${CONFIG_FG_INTERVAL}
  /config_start_time/c\
  config_start_time = '$curr_utc'
  /config_stop_time/c\
  config_stop_time = '$end_utc'
  /config_met_prefix/c\
  config_met_prefix= 'FILE'
  /config_blend_bdy_terrain/c\
  config_blend_bdy_terrain = true
  /config_block_decomp_file_prefix/c\
  config_block_decomp_file_prefix= '${MPAS_GRID}.graph.info.part.'
EOF
  sed -f script.sed ${RUN_DIR}/${NML_INIT} >! ${NML_INIT}
#
# in case of USE_RESTART
  cat >! streams.sed << EOF
/<immutable_stream name="input"/,/<\/*immutable_stream>/ {
s/filename_template="static.nc"/filename_template="${MPAS_GRID}.init.nc"/ }
/<stream name="da_ic"/,/<\/*stream>/ {
s/filename_template="init.nc"/filename_template="${MPAS_GRID}.init_dummy.nc"/ }
EOF
# INITIAL_FCST_DOES_NOT_NEED_TO_USE_RESTART
#
  sed -f streams.sed ${RUN_DIR}/${STREAM_INIT}  >! ${STREAM_INIT}
#
  ${LINK} ${icfile} .
#
  # Run init version of MPAS to create initial condition file
  # To consider run this without PBS

  @ ndecomp = $MODEL_NODES * $N_PROCS
  mpiexec -n ${ndecomp} ./init_atmosphere_model  || exit 2

  ${REMOVE} FILE:*

#  # Check the output file
  set fout = lbc
# 
  ${COPY} -r ${fout}* ${target_dir}
# 
  # In the case of using GFS for ensemble ICs,
  # the LBC is expected to be very similar
  # any solution?
  #
#  if ( ${EXT_DATA_TYPE} == "GFS" ) then
#
#      # create filter_in.txt and filter_out.txt
#      # also copy files
#      ${LINK} ${RUN_DIR}/filter                     .   || exit 1
#      ${LINK} ${RUN_DIR}/advance_time               .   || exit 1
#
#      if ( -f filter_in.txt ) ${REMOVE} filter_in.txt
#      if ( -f filter_out.txt) ${REMOVE} filter_out.txt
#
#      cat >! filter_in.txt << EOF
#${target_dir}/${fout}
#EOF
#
#      set n = 1 
#      while ( $n <= $ENS_SIZE ) 
#
#          set num = `printf "%02d" $n`
#          set ensmember_dir = ${INIT_DIR}/${idate}/${ENS_DIR}${num}
#          mkdir -p ${ensmember_dir}
#          ${COPY} -r ${fout} ${ensmember_dir}
#          echo "${ensmember_dir}/${fout}" >> filter_out.txt 
#
#          @ n++
#
#      end
#
#      # change input.nml
#      # if you want to increase magnitude, change amplitude
#      cat >! input.nml.sed << EOF
#      /obs_sequence_in_name/c\
#      obs_sequence_in_name = 'obs_seq1.out'
#      /perturb_from_single_instance/c\
#      perturb_from_single_instance = .true.
#      /model_perturbation_amplitude/c\
#      model_perturbation_amplitude = 0.0001
#      /ens_size/c\
#      ens_size= ${ENS_SIZE}
#      /init_template_filename/c\
#      init_template_filename = '${target_dir}/${fout}'
#      /use_u_for_wind/c\
#      use_u_for_wind = .true.
#      /update_u_from_reconstruct/c\
#      update_u_from_reconstruct = .false.
#      /'uReconstructZonal',     'QTY_U_WIND_COMPONENT',/c\
#                          'u',                     'QTY_EDGE_NORMAL_SPEED',
#      /'uReconstructMeridional','QTY_V_WIND_COMPONENT',/d
#      /filter_kind/,+11d
#EOF
#      # TODO : might not delete namelist block at assim_tools_mod in future
#      sed -f input.nml.sed ${RUN_DIR}/input.nml >! input.nml
#
#      # update time information at obs_seq file.
#      set gtime = `echo $curr_utc 0 -g | ./advance_time `
#      set gday = `echo $gtime | awk '{ print $1}'`
#      set gsec = `echo $gtime | awk '{ print $2}'`
#
#      cat >! obsseq.sed << EOF
#     /0     151945/c\
#    ${gsec} ${gday}
#EOF
#
#      sed -f obsseq.sed ${RUN_DIR}/obs_seq1.out >! obs_seq1.out
#
#      # run filter to add perturbations
#      ./filter
#  else
#      echo "No need to run filter at this tep"
#      echo "${EXT_DATA_TYPE} is employed here"
#  endif
#
## clean up : may copy logfile
#  ${COPY} dart_log.out ${OUTPUT_DIR}/logs/${idate}/dart_filter_add_perturbation.out
#
#  foreach rfile ( `ls -1 *` )
#    if ( $rfile != $fout )  ${REMOVE} $rfile
#  end
