#!/bin/tcsh
#
# DART software - Copyright UCAR. This open source software is provided
# by UCAR, "as is", without charge, subject to all terms of use at
# http://www.image.ucar.edu/DAReS/DART/DART_download
#
#set echo
########################################################################################
# Create experimental directories for MPAS-DART tutorial
########################################################################################
# General configuration from params.tcsh
#
if ( $#argv >= 1 ) then
   set fn_param = ${1}
else
   set fn_param = `pwd`/params.tcsh
endif

if(! -e $fn_param ) then
   echo $fn_param does not exist. Cannot proceed.
   exit
endif

source $fn_param

# current location
set SCRIPTS_DIR = `pwd`

#create experimental directories
mkdir -p ${BASE_DIR}
cd ${BASE_DIR}

mkdir -p ${RUN_DIR} ${OBS_DIR} ${OUTPUT_DIR} ${CSH_DIR} ${EXE_DIR} ${EXTM_DIR} ${TEMPLATE_DIR}

  echo
  echo "Copy MPAS-DART executables from ${DART_DIR}"
  if ( ${USE_REGIONAL} == "true" ) then
     set dart_exe_list = ( "closest_member_tool" "filter" "model_mod_check" "perfect_model_obs" "perturb_single_instance" \
               "wakeup_filter" "advance_time" "create_fixed_network_seq" "create_obs_sequence"                \
               "fill_inflation_restart" "obs_common_subset" "obs_diag" "obs_selection"                        \
               "obs_seq_coverage" "obs_seq_to_netcdf" "obs_seq_verify" "obs_sequence_tool"                    \
               "mpas_dart_obs_preprocess" "update_bc" "update_mpas_states" )
  else
     set dart_exe_list = ( "closest_member_tool" "filter" "model_mod_check" "perfect_model_obs" "perturb_single_instance" \
               "wakeup_filter" "advance_time" "create_fixed_network_seq" "create_obs_sequence"                \
               "fill_inflation_restart" "obs_common_subset" "obs_diag" "obs_selection"                        \
               "obs_seq_coverage" "obs_seq_to_netcdf" "obs_seq_verify" "obs_sequence_tool"                    \
               "mpas_dart_obs_preprocess" "update_mpas_states" )
  endif

  foreach fn ( ${dart_exe_list} )
     if ( ! -r ${DART_DIR}/models/mpas_atm/work/${fn} ) then
        echo ABORT\: setup.tcsh could not find required readable dependency ${fn}
        exit 1
     else
        ${COPY} -r ${DART_DIR}/models/mpas_atm/work/${fn} ${BASE_DIR}/exec
     endif
  end

# 
# will Copy scripts from shell_script at DART_DIR
  echo "Copy MPAS-DART job scrpts from ${DART_DIR}"
  if ( ${USE_REGIONAL} == "true" ) then
     set sh_list = ( "params.tcsh" "driver_initial_ens.tcsh" "driver_dart_advance.tcsh" "mpas_first_advance.tcsh" "mpas_advance.tcsh" \
                     "assimilate.tcsh" "download.tcsh" "prep_initial_ens_ic.tcsh" "run_obs_preprocess.tcsh" "run_obs_diag.tcsh" "prep_ens_lbc.tcsh" )
  else
     set sh_list = ( "params.tcsh" "driver_initial_ens.tcsh" "driver_dart_advance.tcsh" "mpas_first_advance.tcsh" "mpas_advance.tcsh" \
                     "assimilate.tcsh" "download.tcsh" "prep_initial_ens_ic.tcsh" "run_obs_preprocess.tcsh" "run_obs_diag.tcsh" )
  endif
  foreach fn ( ${sh_list} )
     ## Todo ## final job scripts will be placed into DART_DIR/models/mpas_atm/shell_scripts
     #if ( ! -r ${DART_DIR}/models/mpas_atm/shell_scripts/${fn} ) then
     #   echo ABORT\: setup.tcsh could not find required readable dependency ${fn}
     #   #exit 1
     #else
        ## Todo ## Currently, the directory where we run 'setup.tcsh' will contain other scripts
        #${COPY} -r ${DART_DIR}/models/mpas_atm/work/${fn} ${BASE_DIR}/scripts
        ${COPY} -r ${SCRIPTS_DIR}/${fn} ${BASE_DIR}/scripts
     #endif
  end

  # Todo place tutorial data can be accessible at terminal
  # download and untar tutorial data
  echo
  echo "Download tutorial data and untar them at ${BASE_DIR}"
  echo "However, it is currently not viable to download tutorial data at script"
  echo "unless a specific tool is employed from google drive at terminal."
  echo
  # this is for global mpas-dart tutorial material ; need to upload
  #  echo "please download it from web_broswer and place it to ${SCRIPTS_DIR} for now"
  #echo "https://drive.google.com/file/d/175dxvoQki3CN8-fnayQV_EBYb3mvQTxj/view?usp=sharing"
  #echo

  # This will be placed into google drive link
  if ( ${USE_REGIONAL} == "true" ) then
      set FNAME_TUTORIAL = regional_template.tgz
  else
      set FNAME_TUTORIAL = tutorial_data_202412.tgz
  endif
  if ( ! -e ${SCRIPTS_DIR}/${FNAME_TUTORIAL} ) then
     echo ABORT\: ${FNAME_TUTORIAL} is not available.
     echo Please place it to this directory in the first hand
     echo if you are using derecho,
     echo copy /glade/derecho/scratch/junpark/tutorial_data_202412.tgz for global
     echo copy copy /glade/derecho/scratch/junpark/202504/mpas-dart_tutorial_scripts/regional_template.tgz for regional
     exit 1
  else
     ${COPY} -r ${SCRIPTS_DIR}/${FNAME_TUTORIAL} ${BASE_DIR}
     tar -zxvf ${FNAME_TUTORIAL}
  endif
